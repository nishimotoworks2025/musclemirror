import 'dart:async';
import 'dart:convert';
import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:app_links/app_links.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import '../config/app_config.dart';
import 'billing_api_client.dart';

/// AWS Cognito authentication service (shared with TrueSkin).
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  
  late final CognitoUserPool _userPool;
  CognitoUser? _cognitoUser;
  CognitoUserSession? _session;

  final _appLinks = AppLinks();
  StreamSubscription? _linkSubscription;

  final _authStateController = StreamController<bool>.broadcast();
  Stream<bool> get authStateChanges => _authStateController.stream;

  AuthService._internal() {
    _userPool = CognitoUserPool(
      AppConfig.userPoolId,
      AppConfig.userPoolClientId,
    );
    _initDeepLinkListener();
  }

  void _initDeepLinkListener() {
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == 'musclemirror') {
        if (uri.host == 'callback') {
          _handleRedirect(uri);
        } else if (uri.host == 'logout') {
          // Handle successful logout redirect if needed
          _authStateController.add(false);
        }
      }
    });
  }

  void dispose() {
    _linkSubscription?.cancel();
    _authStateController.close();
  }

  /// Check if user is currently authenticated.
  bool get isAuthenticated => _session?.isValid() ?? false;

  /// Get current user's email.
  String? get userEmail => _cognitoUser?.username;

  /// Get current access token.
  String? get accessToken => _session?.getAccessToken().getJwtToken();

  /// Get current ID token.
  String? get idToken => _session?.getIdToken().getJwtToken();

  /// Sign in with email and password.
  Future<AuthResult> signIn(String email, String password) async {
    _cognitoUser = CognitoUser(email, _userPool);
    final authDetails = AuthenticationDetails(
      username: email,
      password: password,
    );

    try {
      _session = await _cognitoUser!.authenticateUser(authDetails);
      _authStateController.add(true);
      return AuthResult.success();
    } on CognitoUserNewPasswordRequiredException {
      return AuthResult.failure('新しいパスワードの設定が必要です');
    } on CognitoUserMfaRequiredException {
      return AuthResult.failure('MFA認証が必要です');
    } on CognitoUserConfirmationNecessaryException {
      return AuthResult.failure('メール認証が必要です');
    } on CognitoClientException catch (e) {
      return AuthResult.failure(e.message ?? '認証エラーが発生しました');
    } catch (e) {
      return AuthResult.failure('ログインに失敗しました: $e');
    }
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    if (_cognitoUser != null) {
      await _cognitoUser!.signOut();
      _cognitoUser = null;
      _session = null;
      _authStateController.add(false);

      // Also clear Cognito session in browser to force account selection next time
      final clientId = AppConfig.userPoolClientId;
      final logoutUri = 'musclemirror://logout';
      final domain = AppConfig.cognitoDomain;
      
      final logoutUrlStr = 'https://$domain/logout?client_id=$clientId&logout_uri=$logoutUri';
      final logoutUrl = Uri.parse(logoutUrlStr);
      
      // Use flutter_web_auth_2 to perform logout then capture the redirect and close
      try {
        await FlutterWebAuth2.authenticate(
          url: logoutUrl.toString(),
          callbackUrlScheme: 'musclemirror',
          options: const FlutterWebAuth2Options(
            intentFlags: ephemeralIntentFlags,
          ),
        );
      } catch (e) {
        // flutter_web_auth_2 throws an exception if the user cancels or if it finishes
        // Depending on how Cognito's logout works, it might just return cleanly or throw
        print('Logout web auth message: $e');
      }
    }
  }

  /// Delete the current user's account.
  Future<AuthResult> deleteAccount() async {
    if (_cognitoUser == null || !isAuthenticated) {
      return AuthResult.failure('ログインしていません');
    }

    try {
      // 1. Delete user data on the server first (requires valid token)
      final billingApiClient = BillingApiClient();
      await billingApiClient.deleteAccount();

      // 2. Delete user from Cognito
      await _cognitoUser!.deleteUser();
      
      _cognitoUser = null;
      _session = null;
      _authStateController.add(false);
      return AuthResult.success();
    } on CognitoClientException catch (e) {
      if (e.code == 'NotAuthorizedException') {
        return AuthResult.failure('セキュリティ保護のため、アカウント削除には再ログインが必要です。一度ログアウトしてから再度お試しください。');
      }
      return AuthResult.failure('アカウントの削除に失敗しました: ${e.message}');
    } catch (e) {
      return AuthResult.failure('アカウントの削除に失敗しました: $e');
    }
  }

  /// Sign up with email and password.
  /// User Pool is configured for email alias, so username must not be email format.
  Future<AuthResult> signUp(String email, String password) async {
    // Generate a unique username (User Pool uses email as alias)
    final username = 'user_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final userAttributes = [
        AttributeArg(name: 'email', value: email),
      ];
      await _userPool.signUp(username, password, userAttributes: userAttributes);
      return AuthResult.success(data: username); // Return generated username for confirmation
    } on CognitoClientException catch (e) {
      if (e.code == 'UsernameExistsException') {
        return AuthResult.failure('このメールアドレスはすでに登録されています');
      }
      if (e.code == 'InvalidPasswordException') {
        return AuthResult.failure('パスワードの形式が正しくありません（大文字・小文字・数字を含む8文字以上）');
      }
      return AuthResult.failure(e.message ?? '登録エラーが発生しました');
    } catch (e) {
      return AuthResult.failure('登録に失敗しました: $e');
    }
  }

  /// Confirm sign up with verification code.
  Future<AuthResult> confirmSignUp(String username, String code) async {
    final cognitoUser = CognitoUser(username, _userPool);
    try {
      await cognitoUser.confirmRegistration(code);
      return AuthResult.success();
    } on CognitoClientException catch (e) {
      if (e.code == 'CodeMismatchException') {
        return AuthResult.failure('確認コードが正しくありません');
      }
      if (e.code == 'ExpiredCodeException') {
        return AuthResult.failure('確認コードの有効期限が切れています。再送信してください');
      }
      return AuthResult.failure(e.message ?? '確認エラーが発生しました');
    } catch (e) {
      return AuthResult.failure('確認に失敗しました: $e');
    }
  }

  /// Resend confirmation code.
  Future<AuthResult> resendConfirmationCode(String username) async {
    final cognitoUser = CognitoUser(username, _userPool);
    try {
      await cognitoUser.resendConfirmationCode();
      return AuthResult.success();
    } on CognitoClientException catch (e) {
      return AuthResult.failure(e.message ?? '再送信エラーが発生しました');
    } catch (e) {
      return AuthResult.failure('再送信に失敗しました: $e');
    }
  }

  /// Send password reset code to email.
  Future<AuthResult> forgotPassword(String email) async {
    final cognitoUser = CognitoUser(email, _userPool);
    try {
      await cognitoUser.forgotPassword();
      return AuthResult.success();
    } on CognitoClientException catch (e) {
      if (e.code == 'UserNotFoundException') {
        return AuthResult.failure('このメールアドレスは登録されていません');
      }
      if (e.code == 'LimitExceededException') {
        return AuthResult.failure('試行回数が多すぎます。しばらく待ってから再度お試しください');
      }
      return AuthResult.failure(e.message ?? 'パスワードリセットの送信に失敗しました');
    } catch (e) {
      return AuthResult.failure('送信に失敗しました: $e');
    }
  }

  /// Confirm new password with reset code.
  Future<AuthResult> confirmForgotPassword(
      String email, String code, String newPassword) async {
    final cognitoUser = CognitoUser(email, _userPool);
    try {
      await cognitoUser.confirmPassword(code, newPassword);
      return AuthResult.success();
    } on CognitoClientException catch (e) {
      if (e.code == 'CodeMismatchException') {
        return AuthResult.failure('確認コードが正しくありません');
      }
      if (e.code == 'ExpiredCodeException') {
        return AuthResult.failure('確認コードの有効期限が切れています。再度送信してください');
      }
      if (e.code == 'InvalidPasswordException') {
        return AuthResult.failure('パスワードの形式が正しくありません（大文字・小文字・数字を含む8文字以上）');
      }
      return AuthResult.failure(e.message ?? 'パスワードの変更に失敗しました');
    } catch (e) {
      return AuthResult.failure('パスワードの変更に失敗しました: $e');
    }
  }

  /// Sign in with Google.
  Future<AuthResult> signInWithGoogle() async {
    return _signInWithSocialProvider('Google');
  }

  /// Sign in with LINE.
  Future<AuthResult> signInWithLine() async {
    return _signInWithSocialProvider('LINE');
  }

  Future<AuthResult> _signInWithSocialProvider(String provider) async {
    final domain = AppConfig.cognitoDomain;
    final clientId = AppConfig.userPoolClientId;
    final redirectUri = 'musclemirror://callback';
    
    final url = Uri.https(
      domain,
      '/oauth2/authorize',
      {
        'identity_provider': provider,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'client_id': clientId,
        'scope': 'openid profile',
        'prompt': 'select_account',
      },
    );

    try {
      final result = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: 'musclemirror',
        options: const FlutterWebAuth2Options(
          intentFlags: ephemeralIntentFlags,
        ),
      );
      
      // Parse the result string into a Uri
      final resultUri = Uri.parse(result);
      // Process the redirect
      await _handleRedirect(resultUri);
      
      return AuthResult.success();
    } catch (e) {
      return AuthResult.failure('ログインに失敗しました: $e');
    }
  }

  Future<void> _handleRedirect(Uri uri) async {
    final code = uri.queryParameters['code'];
    if (code == null) return;

    try {
      final tokenUrl = Uri.parse('https://${AppConfig.cognitoDomain}/oauth2/token');
      final response = await http.post(
        tokenUrl,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'client_id': AppConfig.userPoolClientId,
          'code': code,
          'redirect_uri': 'musclemirror://callback',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final idToken = data['id_token'];
        final accessToken = data['access_token'];
        final refreshToken = data['refresh_token'];

        // Create session and user
        final cognitoIdToken = CognitoIdToken(idToken);
        final cognitoAccessToken = CognitoAccessToken(accessToken);
        final cognitoRefreshToken = CognitoRefreshToken(refreshToken);
        
        _session = CognitoUserSession(cognitoIdToken, cognitoAccessToken, refreshToken: cognitoRefreshToken);
        _cognitoUser = CognitoUser(
          cognitoIdToken.payload['email'] ?? cognitoIdToken.payload['sub'], 
          _userPool,
          signInUserSession: _session,
        );
        
        _authStateController.add(true);
      } else {
        print('Token exchange failed: ${response.body}');
      }
    } catch (e) {
      print('Error during token exchange: $e');
    }
  }

  /// Try to restore session from stored credentials.
  Future<bool> restoreSession() async {
    // Note: In a real app, you would implement secure storage
    // to persist and restore the session.
    return false;
  }

  /// Get user attributes.
  Future<Map<String, String>> getUserAttributes() async {
    if (_cognitoUser == null || !isAuthenticated) {
      return {};
    }

    try {
      final attributes = await _cognitoUser!.getUserAttributes();
      if (attributes == null) return {};

      final result = <String, String>{};
      for (final attr in attributes) {
        if (attr.name != null && attr.value != null) {
          result[attr.name!] = attr.value!;
        }
      }
      return result;
    } catch (e) {
      return {};
    }
  }
}

/// Result of an authentication operation.
class AuthResult {
  final bool success;
  final String? errorMessage;
  final String? data; // e.g., generated username returned from signUp

  AuthResult._({required this.success, this.errorMessage, this.data});

  factory AuthResult.success({String? data}) => AuthResult._(success: true, data: data);
  factory AuthResult.failure(String message) =>
      AuthResult._(success: false, errorMessage: message);
}
