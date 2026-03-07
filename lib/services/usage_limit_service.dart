import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_mode_service.dart';
import 'device_id_service.dart';
import 'billing_api_client.dart';
import 'billing_service.dart';

/// Usage limits per user mode.
class UsageLimits {
  static const int proDailyLimit = 3;
  static const int freeDailyLimit = 1;
  static const int guestTotalLimit = 3;
}

/// Service for tracking and enforcing usage limits based on user mode.
///
/// - Pro: 3 diagnoses per day
/// - Free: 1 diagnosis per day
/// - Guest: 3 total diagnoses (device-bound, survives reinstall)
class UsageLimitService {
  static final UsageLimitService _instance = UsageLimitService._internal();
  factory UsageLimitService() => _instance;
  UsageLimitService._internal();

  final UserModeService _userModeService = UserModeService();
  final DeviceIdService _deviceIdService = DeviceIdService();

  // SharedPreferences keys
  static const String _dailyUsedCountKey = 'usage_daily_count';
  static const String _dailyKeyKey = 'usage_daily_key';

  /// Check if the current user can perform a diagnosis.
  Future<bool> canUse() async {
    final mode = _userModeService.currentMode;
    switch (mode) {
      case UserMode.pro:
        if (BillingService().hasActiveSubscription) {
          return await _getDailyUsedCount() < UsageLimits.proDailyLimit;
        } else {
          // チケットが1枚以上あれば使用可能（日次制限なし・翌日も有効）
          return BillingService().ticketCount > 0;
        }
      case UserMode.free:
        return await _getDailyUsedCount() < UsageLimits.freeDailyLimit;
      case UserMode.guest:
        return await _getGuestTotalUsedCount() < UsageLimits.guestTotalLimit;
    }
  }

  /// Record a usage (call after successful diagnosis).
  Future<void> recordUse() async {
    final mode = _userModeService.currentMode;
    final prefs = await SharedPreferences.getInstance();

    if (mode == UserMode.guest) {
      final deviceId = await _deviceIdService.getDeviceId();
      try {
        await BillingApiClient().incrementGuestUsage(deviceId);
        debugPrint('UsageLimitService: Guest usage incremented via API');
      } catch (e) {
        debugPrint('UsageLimitService: Failed to increment guest usage: $e');
        // Optionally fallback to local storage if API fails
      }
    } else if (mode == UserMode.pro && !BillingService().hasActiveSubscription) {
      // チケットユーザー: チケットを1枚消費（日次カウントは管理しない）
      await BillingService().consumeTicket();
      debugPrint('UsageLimitService: Ticket consumed. Remaining: ${BillingService().ticketCount}');
    } else {
      // Pro（サブスク）or Free: 日次カウント管理
      final todayKey = _todayKey();
      final storedKey = prefs.getString(_dailyKeyKey);

      if (storedKey != todayKey) {
        // New day, reset counter
        await prefs.setString(_dailyKeyKey, todayKey);
        await prefs.setInt(_dailyUsedCountKey, 1);
        debugPrint('UsageLimitService: New day, count reset to 1');
      } else {
        final current = prefs.getInt(_dailyUsedCountKey) ?? 0;
        await prefs.setInt(_dailyUsedCountKey, current + 1);
        debugPrint('UsageLimitService: Daily used: ${current + 1}');
      }
    }
  }

  /// Get remaining usage count for current mode.
  Future<int> getRemainingCount() async {
    final mode = _userModeService.currentMode;
    switch (mode) {
      case UserMode.pro:
        if (BillingService().hasActiveSubscription) {
          final used = await _getDailyUsedCount();
          return (UsageLimits.proDailyLimit - used).clamp(0, UsageLimits.proDailyLimit);
        } else {
          // チケット枚数のみ（日次カウントは加算しない）
          return BillingService().ticketCount;
        }
      case UserMode.free:
        final used = await _getDailyUsedCount();
        return (UsageLimits.freeDailyLimit - used).clamp(0, UsageLimits.freeDailyLimit);
      case UserMode.guest:
        final used = await _getGuestTotalUsedCount();
        return (UsageLimits.guestTotalLimit - used).clamp(0, UsageLimits.guestTotalLimit);
    }
  }

  /// Get the limit for current mode.
  int getLimit() {
    final mode = _userModeService.currentMode;
    switch (mode) {
      case UserMode.pro:
        if (BillingService().hasActiveSubscription) {
          return UsageLimits.proDailyLimit;
        } else {
          // チケット枚数のみ
          return BillingService().ticketCount;
        }
      case UserMode.free:
        return UsageLimits.freeDailyLimit;
      case UserMode.guest:
        return UsageLimits.guestTotalLimit;
    }
  }

  /// Get a human-readable description of the limit.
  String getLimitDescription() {
    final mode = _userModeService.currentMode;
    switch (mode) {
      case UserMode.pro:
        if (BillingService().hasActiveSubscription) {
          return '1日${UsageLimits.proDailyLimit}回まで';
        } else {
          return 'チケット残り: ${BillingService().ticketCount}回';
        }
      case UserMode.free:
        return '1日${UsageLimits.freeDailyLimit}回まで';
      case UserMode.guest:
        return '合計${UsageLimits.guestTotalLimit}回まで';
    }
  }

  // --- Private helpers ---

  Future<int> _getDailyUsedCount() async {
    final prefs = await SharedPreferences.getInstance();
    final storedKey = prefs.getString(_dailyKeyKey);
    final todayKey = _todayKey();

    if (storedKey != todayKey) {
      // Different day, count is effectively 0
      return 0;
    }
    return prefs.getInt(_dailyUsedCountKey) ?? 0;
  }

  Future<int> _getGuestTotalUsedCount() async {
    final deviceId = await _deviceIdService.getDeviceId();
    try {
      return await BillingApiClient().fetchGuestUsage(deviceId);
    } catch (e) {
      debugPrint('UsageLimitService: Failed to fetch guest usage: $e');
      return 0;
    }
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
