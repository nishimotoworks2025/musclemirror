import 'dart:async';
import 'dart:convert';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'billing_api_client.dart';
import 'billing_service.dart';
import 'history_service.dart';

class AuthService {
  static const Duration _socialLoginTimeout = Duration(seconds: 60);

  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  final StreamController<bool> _authStateController =
      StreamController<bool>.broadcast();

  bool _configured = false;
  bool _isAuthenticated = false;
  String? _accessToken;
  String? _idToken;
  String? _userEmail;
  String? _currentUserId;

  Stream<bool> get authStateChanges => _authStateController.stream;
  bool get isAuthenticated => _isAuthenticated;
  String? get userEmail => _userEmail;
  String? get accessToken => _accessToken;
  String? get idToken => _idToken;
  String? get currentUserId => _currentUserId;

  AuthService._internal();

  Future<void> initialize() async {
    await _configure();
    await restoreSession();
  }

  void dispose() {
    _authStateController.close();
  }

  Future<void> _configure() async {
    if (_configured) {
      return;
    }

    try {
      await Amplify.addPlugins([AmplifyAuthCognito()]);
      await Amplify.configure(AppConfig.amplifyJson);
    } on AmplifyAlreadyConfiguredException {
      // Another singleton instance or a previous app start already configured it.
    }

    _configured = true;
  }

  Future<AuthResult> signIn(String email, String password) async {
    await _configure();
    final normalizedEmail = email.trim().toLowerCase();

    try {
      await Amplify.Auth.signOut();
    } catch (_) {
      // Ignore stale-session cleanup failures.
    }

    try {
      final result = await Amplify.Auth.signIn(
        username: normalizedEmail,
        password: password,
        options: const SignInOptions(
          pluginOptions: CognitoSignInPluginOptions(
            authFlowType: AuthenticationFlowType.userSrpAuth,
          ),
        ),
      );

      if (!result.isSignedIn) {
        return AuthResult.failure('ログインを完了できませんでした');
      }

      await _refreshCachedSession(notify: true);
      return AuthResult.success();
    } on AuthException catch (e) {
      return AuthResult.failure(_mapAuthException(e));
    } catch (e) {
      return AuthResult.failure('ログインに失敗しました: $e');
    }
  }

  Future<void> signOut() async {
    await _configure();

    try {
      await Amplify.Auth.signOut(
        options: const SignOutOptions(globalSignOut: true),
      );
    } catch (e) {
      debugPrint('AuthService: signOut failed: $e');
    }

    _clearCachedSession(notify: true);

    try {
      await BillingService().clearLocalEntitlements();
    } catch (e) {
      debugPrint(
        'AuthService: failed to clear local entitlements on sign out: $e',
      );
    }
  }

  Future<AuthResult> signUp(String email, String password) async {
    await _configure();
    final normalizedEmail = email.trim().toLowerCase();
    final username = 'user_${DateTime.now().millisecondsSinceEpoch}';

    try {
      await Amplify.Auth.signUp(
        username: username,
        password: password,
        options: SignUpOptions(
          userAttributes: {AuthUserAttributeKey.email: normalizedEmail},
          pluginOptions: const CognitoSignUpPluginOptions(),
        ),
      );
      return AuthResult.success(data: username);
    } on AuthException catch (e) {
      return AuthResult.failure(_mapAuthException(e));
    } catch (e) {
      return AuthResult.failure('新規登録に失敗しました: $e');
    }
  }

  Future<AuthResult> confirmSignUp(String username, String code) async {
    await _configure();

    try {
      await Amplify.Auth.confirmSignUp(
        username: username,
        confirmationCode: code,
      );
      return AuthResult.success();
    } on AuthException catch (e) {
      return AuthResult.failure(_mapAuthException(e));
    } catch (e) {
      return AuthResult.failure('確認コードの検証に失敗しました: $e');
    }
  }

  Future<AuthResult> resendConfirmationCode(String username) async {
    await _configure();

    try {
      await Amplify.Auth.resendSignUpCode(username: username);
      return AuthResult.success();
    } on AuthException catch (e) {
      return AuthResult.failure(_mapAuthException(e));
    } catch (e) {
      return AuthResult.failure('確認コードの再送に失敗しました: $e');
    }
  }

  Future<AuthResult> forgotPassword(String email) async {
    await _configure();
    final normalizedEmail = email.trim().toLowerCase();

    try {
      await Amplify.Auth.resetPassword(username: normalizedEmail);
      return AuthResult.success();
    } on AuthException catch (e) {
      return AuthResult.failure(_mapAuthException(e));
    } catch (e) {
      return AuthResult.failure('パスワードリセットに失敗しました: $e');
    }
  }

  Future<AuthResult> confirmForgotPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    await _configure();
    final normalizedEmail = email.trim().toLowerCase();

    try {
      await Amplify.Auth.confirmResetPassword(
        username: normalizedEmail,
        newPassword: newPassword,
        confirmationCode: code,
      );
      return AuthResult.success();
    } on AuthException catch (e) {
      return AuthResult.failure(_mapAuthException(e));
    } catch (e) {
      return AuthResult.failure('パスワード再設定に失敗しました: $e');
    }
  }

  Future<AuthResult> signInWithGoogle() async {
    return _signInWithSocialProvider(AuthProvider.google);
  }

  Future<AuthResult> signInWithLine() async {
    return _signInWithSocialProvider(const AuthProvider.custom('LINE'));
  }

  Future<AuthResult> _signInWithSocialProvider(AuthProvider provider) async {
    await _configure();

    try {
      await Amplify.Auth.signOut();
    } catch (_) {
      // Ignore stale-session cleanup failures.
    }

    try {
      final result = await Amplify.Auth.signInWithWebUI(
        provider: provider,
        options: const SignInWithWebUIOptions(
          pluginOptions: CognitoSignInWithWebUIPluginOptions(
            isPreferPrivateSession: false,
          ),
        ),
      ).timeout(_socialLoginTimeout);

      if (!result.isSignedIn) {
        return AuthResult.failure('ソーシャルログインを完了できませんでした');
      }

      await _refreshCachedSession(notify: true);
      return AuthResult.success();
    } on UserCancelledException {
      return AuthResult.failure('ログインをキャンセルしました');
    } on TimeoutException {
      return AuthResult.failure('ログインがタイムアウトしました。もう一度お試しください。');
    } on AuthException catch (e) {
      return AuthResult.failure(_mapAuthException(e));
    } catch (e) {
      return AuthResult.failure('ログインに失敗しました: $e');
    }
  }

  Future<bool> restoreSession() async {
    await _configure();
    return _refreshCachedSession(notify: true);
  }

  Future<String?> getValidIdToken() async {
    if (_isAuthenticated && _idToken != null && _idToken!.isNotEmpty) {
      return _idToken;
    }

    final restored = await restoreSession();
    if (!restored) {
      return null;
    }
    return _idToken;
  }

  Future<String?> getBestEffortIdToken() async {
    return getValidIdToken();
  }

  Future<AuthResult> deleteAccountFixed() async {
    try {
      final idToken = await getBestEffortIdToken();
      if (idToken == null || idToken.isEmpty) {
        return AuthResult.failure('ログイン状態を確認できませんでした。再ログイン後にもう一度お試しください。');
      }

      await BillingApiClient().deleteAccount(idToken: idToken);

      try {
        await Amplify.Auth.deleteUser();
      } catch (e) {
        debugPrint('AuthService: deleteUser skipped after backend delete: $e');
      }

      try {
        await HistoryService.clearAll();
      } catch (e) {
        debugPrint('AuthService: failed to clear local history: $e');
      }

      try {
        await BillingService().clearLocalEntitlements();
      } catch (e) {
        debugPrint('AuthService: failed to clear billing cache: $e');
      }

      _clearCachedSession(notify: true);
      return AuthResult.success();
    } catch (e) {
      debugPrint('AuthService: deleteAccountFixed failed: $e');
      return AuthResult.failure('アカウント削除に失敗しました: $e');
    }
  }

  Future<Map<String, String>> getUserAttributes() async {
    if (!_isAuthenticated) {
      return {};
    }

    await _configure();

    try {
      final attributes = await Amplify.Auth.fetchUserAttributes();
      return {
        for (final attr in attributes) attr.userAttributeKey.key: attr.value,
      };
    } catch (e) {
      debugPrint('AuthService: fetchUserAttributes failed: $e');
      return {};
    }
  }

  Future<bool> _refreshCachedSession({required bool notify}) async {
    final wasAuthenticated = _isAuthenticated;
    final previousIdToken = _idToken;

    try {
      final session = await Amplify.Auth.fetchAuthSession();
      if (session is! CognitoAuthSession || !session.isSignedIn) {
        _clearCachedSession(notify: notify && wasAuthenticated);
        return false;
      }

      final tokens = session.userPoolTokensResult.valueOrNull;
      if (tokens == null) {
        _clearCachedSession(notify: notify && wasAuthenticated);
        return false;
      }

      _accessToken = tokens.accessToken.raw;
      _idToken = tokens.idToken.raw;
      _currentUserId = _decodeJwtClaim(_idToken, 'sub');
      _userEmail =
          _decodeJwtClaim(_idToken, 'email') ??
          await _loadEmailFromAttributes() ??
          await _loadUsername();
      _isAuthenticated = true;

      if (notify && (!wasAuthenticated || previousIdToken != _idToken)) {
        _authStateController.add(true);
      }
      return true;
    } catch (e) {
      debugPrint('AuthService: session restoration failed: $e');
      _clearCachedSession(notify: notify && wasAuthenticated);
      return false;
    }
  }

  Future<String?> _loadEmailFromAttributes() async {
    try {
      final attributes = await Amplify.Auth.fetchUserAttributes();
      for (final attribute in attributes) {
        if (attribute.userAttributeKey == AuthUserAttributeKey.email) {
          return attribute.value;
        }
      }
    } catch (e) {
      debugPrint('AuthService: email attribute lookup failed: $e');
    }
    return null;
  }

  Future<String?> _loadUsername() async {
    try {
      final user = await Amplify.Auth.getCurrentUser();
      return user.username;
    } catch (e) {
      debugPrint('AuthService: current user lookup failed: $e');
      return null;
    }
  }

  String? _decodeJwtClaim(String? token, String claim) {
    if (token == null || token.isEmpty) {
      return null;
    }

    try {
      final parts = token.split('.');
      if (parts.length < 2) {
        return null;
      }
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final data = json.decode(payload) as Map<String, dynamic>;
      final value = data[claim];
      return value?.toString();
    } catch (e) {
      debugPrint('AuthService: failed to decode JWT claim "$claim": $e');
      return null;
    }
  }

  void _clearCachedSession({required bool notify}) {
    _isAuthenticated = false;
    _accessToken = null;
    _idToken = null;
    _userEmail = null;
    _currentUserId = null;

    if (notify) {
      _authStateController.add(false);
    }
  }

  String _mapAuthException(AuthException exception) {
    final message = exception.message;

    if (message.contains('Incorrect username or password') ||
        message.contains('NotAuthorizedException')) {
      return 'メールアドレスまたはパスワードが正しくありません';
    }
    if (message.contains('UserNotFoundException')) {
      return 'このメールアドレスは登録されていません';
    }
    if (message.contains('UsernameExistsException')) {
      return 'このメールアドレスは既に登録されています';
    }
    if (message.contains('InvalidPasswordException')) {
      return 'パスワードの形式が正しくありません。英大文字・英小文字・数字を含む8文字以上で入力してください';
    }
    if (message.contains('InvalidParameterException') ||
        message.contains('Invalid parameter') ||
        message.contains('format')) {
      return message.isEmpty
          ? '入力形式が正しくありません。メールアドレスとパスワードを確認してください'
          : '入力形式エラー: $message';
    }
    if (message.contains('CodeMismatchException')) {
      return '確認コードが正しくありません';
    }
    if (message.contains('ExpiredCodeException')) {
      return '確認コードの有効期限が切れています';
    }
    if (message.contains('LimitExceededException')) {
      return '試行回数が上限に達しました。しばらく待ってから再度お試しください';
    }
    if (message.contains('UserNotConfirmedException')) {
      return 'メール確認が完了していません';
    }

    return message.isEmpty ? '認証に失敗しました' : message;
  }
}

class AuthResult {
  final bool success;
  final String? errorMessage;
  final String? data;

  AuthResult._({required this.success, this.errorMessage, this.data});

  factory AuthResult.success({String? data}) =>
      AuthResult._(success: true, data: data);
  factory AuthResult.failure(String message) =>
      AuthResult._(success: false, errorMessage: message);
}
