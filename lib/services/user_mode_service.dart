import 'dart:async';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'billing_service.dart';

/// User subscription mode
enum UserMode {
  guest, // Not logged in
  free, // Logged in but no subscription
  pro, // Logged in with active subscription
}

/// Service for managing user mode (Pro/Free/Guest)
/// Integrates AuthService and BillingService to determine current user mode
class UserModeService {
  static final UserModeService _instance = UserModeService._internal();
  factory UserModeService() => _instance;
  UserModeService._internal();

  final AuthService _authService = AuthService();
  final BillingService _billingService = BillingService();
  StreamSubscription<bool>? _authSubscription;

  final _modeController = StreamController<UserMode>.broadcast();
  Stream<UserMode> get modeStream => _modeController.stream;

  final _isPro = ValueNotifier<bool>(false);
  ValueNotifier<bool> get isProNotifier => _isPro;

  UserMode _currentMode = UserMode.guest;
  UserMode get currentMode => _currentMode;

  bool get isGuest => _currentMode == UserMode.guest;
  bool get isFree => _currentMode == UserMode.free;
  bool get isPro => _currentMode == UserMode.pro;
  bool get hasActiveSubscription => _billingService.hasActiveSubscription;
  bool get hasTicket => _billingService.hasTicketEntitlement;
  bool get hasProAccess => _billingService.hasProAccess;

  /// Initialize the service
  Future<void> initialize() async {
    if (_authSubscription == null) {
      _authSubscription = _authService.authStateChanges.listen((_) {
        unawaited(_refreshMode());
      });

      _billingService.entitlementVersionNotifier.removeListener(_handleBillingChange);
      _billingService.entitlementVersionNotifier.addListener(_handleBillingChange);
    }

    await _authService.initialize();
    await _billingService.initialize();
    await _refreshMode();
  }

  void _handleBillingChange() {
    unawaited(_refreshMode());
  }

  /// Update current mode based on auth and billing status
  Future<void> _refreshMode() async {
    if (!_authService.isAuthenticated) {
      await _authService.restoreSession();
    }

    final wasMode = _currentMode;

    if (!_authService.isAuthenticated) {
      // Keep users out of Guest when they still have an authenticated account
      // but the session is being refreshed in the background.
      _currentMode = _billingService.hasProAccess ? UserMode.free : UserMode.guest;
    } else if (_billingService.hasProAccess) {
      _currentMode = UserMode.pro;
    } else {
      _currentMode = UserMode.free;
    }

    _isPro.value = _currentMode == UserMode.pro;
    debugPrint(
      'UserModeService: auth=${_authService.isAuthenticated}, '
      'hasActiveSubscription=${_billingService.hasActiveSubscription}, '
      'hasProAccess=${_billingService.hasProAccess}, '
      'mode=$_currentMode',
    );

    if (wasMode != _currentMode) {
      debugPrint(
        'UserModeService: Mode changed from $wasMode to $_currentMode',
      );
    }

    _modeController.add(_currentMode);
  }

  /// Get display text for current mode
  String get modeDisplayText {
    switch (_currentMode) {
      case UserMode.guest:
        return 'Guest';
      case UserMode.free:
        return 'Free';
      case UserMode.pro:
        return 'Pro';
    }
  }

  /// Get Japanese display text for current mode
  String get modeDisplayTextJa {
    switch (_currentMode) {
      case UserMode.guest:
        return 'ゲスト';
      case UserMode.free:
        return '無料';
      case UserMode.pro:
        return 'Pro';
    }
  }

  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;
    _modeController.close();
    _billingService.entitlementVersionNotifier.removeListener(_handleBillingChange);
  }
}
