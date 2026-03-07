import 'dart:async';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'billing_service.dart';

/// User subscription mode
enum UserMode {
  guest,   // Not logged in
  free,    // Logged in but no subscription
  pro,     // Logged in with active subscription
}

/// Service for managing user mode (Pro/Free/Guest)
/// Integrates AuthService and BillingService to determine current user mode
class UserModeService {
  static final UserModeService _instance = UserModeService._internal();
  factory UserModeService() => _instance;
  UserModeService._internal();

  final AuthService _authService = AuthService();
  final BillingService _billingService = BillingService();
  
  final _modeController = StreamController<UserMode>.broadcast();
  Stream<UserMode> get modeStream => _modeController.stream;
  
  final _isPro = ValueNotifier<bool>(false);
  ValueNotifier<bool> get isProNotifier => _isPro;
  
  UserMode _currentMode = UserMode.guest;
  UserMode get currentMode => _currentMode;
  
  bool get isGuest => _currentMode == UserMode.guest;
  bool get isFree => _currentMode == UserMode.free;
  bool get isPro => _currentMode == UserMode.pro;

  /// Initialize the service
  Future<void> initialize() async {
    // Listen to auth state changes
    _authService.authStateChanges.listen((_) {
      _updateMode();
    });
    
    // Initialize billing service automatically on startup
    // This allows silent restore of subscriptions from Google Play
    _billingService.initialize();
    
    // Listen to billing status changes
    _billingService.isProNotifier.addListener(_updateMode);
    
    // Initial mode check
    _updateMode();
  }

  /// Update current mode based on auth and billing status
  void _updateMode() {
    final wasMode = _currentMode;
    
    if (!_authService.isAuthenticated) {
      _currentMode = UserMode.guest;
    } else if (_billingService.isPro) {
      _currentMode = UserMode.pro;
    } else {
      _currentMode = UserMode.free;
    }
    
    _isPro.value = _currentMode == UserMode.pro;
    
    if (wasMode != _currentMode) {
      debugPrint('UserModeService: Mode changed from $wasMode to $_currentMode');
      _modeController.add(_currentMode);
    }
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
    _modeController.close();
    _billingService.isProNotifier.removeListener(_updateMode);
  }
}
