import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'billing_api_client.dart';
import 'billing_service.dart';
import 'device_id_service.dart';
import 'user_mode_service.dart';

String? resolveLegacyDailyKey({
  required String? userId,
  required String? Function(String key) readString,
}) {
  for (final bucket in const ['pro', 'free']) {
    final key = userId != null
        ? '${UsageLimitService.dailyKeyKey}_${userId}_$bucket'
        : '${UsageLimitService.dailyKeyKey}_$bucket';
    final value = readString(key);
    if (value != null) {
      return value;
    }
  }
  return null;
}

int resolveLegacyDailyCount({
  required String? userId,
  required String? storedKey,
  required String? Function(String key) readString,
  required int? Function(String key) readInt,
}) {
  if (storedKey == null) {
    return 0;
  }

  var maxCount = 0;
  for (final bucket in const ['pro', 'free']) {
    final legacyKey = userId != null
        ? '${UsageLimitService.dailyKeyKey}_${userId}_$bucket'
        : '${UsageLimitService.dailyKeyKey}_$bucket';
    if (readString(legacyKey) != storedKey) {
      continue;
    }

    final legacyCountKey = userId != null
        ? '${UsageLimitService.dailyUsedCountKey}_${userId}_$bucket'
        : '${UsageLimitService.dailyUsedCountKey}_$bucket';
    final count = readInt(legacyCountKey) ?? 0;
    if (count > maxCount) {
      maxCount = count;
    }
  }
  return maxCount;
}

int resolveFreeRemainingCount({
  required int localUsed,
  required int? serverUsedToday,
}) {
  final effectiveUsed = localUsed > (serverUsedToday ?? 0)
      ? localUsed
      : (serverUsedToday ?? 0);
  return (UsageLimits.freeDailyLimit - effectiveUsed).clamp(
    0,
    UsageLimits.freeDailyLimit,
  );
}

class UsageLimits {
  static const int proDailyLimit = 3;
  static const int freeDailyLimit = 1;
  static const int guestTotalLimit = 3;
}

class UsageLimitService {
  static final UsageLimitService _instance = UsageLimitService._internal();
  factory UsageLimitService() => _instance;
  UsageLimitService._internal();

  final DeviceIdService _deviceIdService = DeviceIdService();
  final AuthService _authService = AuthService();
  bool _legacyMigrationDone = false;

  static const String _dailyUsedCountKey = 'usage_daily_count';
  static const String _dailyKeyKey = 'usage_daily_key';
  static const String dailyUsedCountKey = _dailyUsedCountKey;
  static const String dailyKeyKey = _dailyKeyKey;

  Future<bool> canUse() async {
    await _authService.restoreSession();
    final mode = _effectiveMode();
    final used = await _getDailyUsedCount();
    final serverRemaining = _getServerRemainingCount();

    debugPrint(
      'UsageLimitService: canUse() - Mode: $mode, Used: $used, UserId: ${_authService.currentUserId}',
    );

    switch (mode) {
      case UserMode.pro:
        if (BillingService().hasActiveSubscription) {
          if (serverRemaining != null) {
            return serverRemaining > 0;
          }
          final limit = _getServerDailyLimit() ?? UsageLimits.proDailyLimit;
          return used < limit;
        }
        return BillingService().ticketCount > 0;
      case UserMode.free:
        if (BillingService().ticketCount > 0) {
          return true;
        }
        return resolveFreeRemainingCount(
              localUsed: used,
              serverUsedToday: BillingService().meStatus?.usedToday,
            ) >
            0;
      case UserMode.guest:
        return await _getGuestTotalUsedCount() < UsageLimits.guestTotalLimit;
    }
  }

  Future<void> recordUse({bool wasTicket = false}) async {
    await _authService.restoreSession();
    final mode = _effectiveMode();
    final prefs = await SharedPreferences.getInstance();

    if (mode == UserMode.guest) {
      final deviceId = await _deviceIdService.getDeviceId();
      try {
        await BillingApiClient().incrementGuestUsage(deviceId);
      } catch (e) {
        debugPrint('UsageLimitService: Failed to increment guest usage: $e');
      }
      return;
    }

    if (wasTicket) {
      debugPrint(
        'UsageLimitService: Ticket used for ${_authService.currentUserId}, skipping daily count increment',
      );
      return;
    }

    // Logged-in usage is enforced by the diagnosis API and reflected in /me.
    // Prefer syncing back to the server result instead of mixing Pro and Free
    // usage locally across entitlement transitions on the same day.
    if (_authService.isAuthenticated && BillingService().meStatus != null) {
      await BillingService().syncWithServer();
      return;
    }

    final userId = _authService.currentUserId;
    final countKey = _dailyCountKeyForUser(userId);
    final keyKey = _dailyKeyForUser(userId);

    final todayKey = _todayKey();
    final storedKey = prefs.getString(keyKey);

    if (storedKey != todayKey) {
      await prefs.setString(keyKey, todayKey);
      await prefs.setInt(countKey, 1);
      debugPrint('UsageLimitService: New day, count reset to 1 for $userId');
      return;
    }

    final current = prefs.getInt(countKey) ?? 0;
    await prefs.setInt(countKey, current + 1);
    debugPrint('UsageLimitService: Daily used for $userId: ${current + 1}');
  }

  Future<int> getRemainingCount() async {
    await _authService.restoreSession();
    final mode = _effectiveMode();
    final used = await _getDailyUsedCount();
    final serverRemaining = _getServerRemainingCount();

    switch (mode) {
      case UserMode.pro:
        if (BillingService().hasActiveSubscription) {
          if (serverRemaining != null) {
            return serverRemaining;
          }
          final limit = _getServerDailyLimit() ?? UsageLimits.proDailyLimit;
          return (limit - used).clamp(0, limit);
        }
        return BillingService().ticketCount;
      case UserMode.free:
        if (BillingService().ticketCount > 0) {
          return BillingService().ticketCount;
        }
        return resolveFreeRemainingCount(
          localUsed: used,
          serverUsedToday: BillingService().meStatus?.usedToday,
        );
      case UserMode.guest:
        final used = await _getGuestTotalUsedCount();
        return (UsageLimits.guestTotalLimit - used).clamp(
          0,
          UsageLimits.guestTotalLimit,
        );
    }
  }

  int getLimit() {
    final mode = _effectiveMode();

    switch (mode) {
      case UserMode.pro:
        if (BillingService().hasActiveSubscription) {
          return _getServerDailyLimit() ?? UsageLimits.proDailyLimit;
        }
        return BillingService().ticketCount;
      case UserMode.free:
        if (BillingService().ticketCount > 0) {
          return BillingService().ticketCount;
        }
        return UsageLimits.freeDailyLimit;
      case UserMode.guest:
        return UsageLimits.guestTotalLimit;
    }
  }

  String getLimitDescription() {
    final mode = _effectiveMode();

    switch (mode) {
      case UserMode.pro:
        if (BillingService().hasActiveSubscription) {
          return 'Daily limit: ${getLimit()}';
        }
        return 'Tickets left: ${BillingService().ticketCount}';
      case UserMode.free:
        if (BillingService().ticketCount > 0) {
          return 'Tickets left: ${BillingService().ticketCount}';
        }
        return 'Daily limit: ${getLimit()}';
      case UserMode.guest:
        return 'Total limit: ${UsageLimits.guestTotalLimit}';
    }
  }

  Future<int> _getDailyUsedCount() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _authService.currentUserId;
    final countKey = _dailyCountKeyForUser(userId);
    final keyKey = _dailyKeyForUser(userId);

    await _migrateLegacyDailyUsageIfNeeded(prefs, userId);

    final storedKey = prefs.getString(keyKey);
    if (storedKey != _todayKey()) {
      return 0;
    }

    final storedCount = prefs.getInt(countKey) ?? 0;
    return storedCount;
  }

  Future<int> _getGuestTotalUsedCount() async {
    await _authService.restoreSession();
    if (_authService.isAuthenticated) {
      return 0;
    }
    final deviceId = await _deviceIdService.getDeviceId();
    try {
      return await BillingApiClient().fetchGuestUsage(deviceId);
    } catch (e) {
      debugPrint('UsageLimitService: Failed to fetch guest usage: $e');
      return 0;
    }
  }

  int? _getServerDailyLimit() {
    if (!_authService.isAuthenticated) {
      return null;
    }
    return BillingService().meStatus?.dailyLimit;
  }

  int? _getServerRemainingCount() {
    if (!_authService.isAuthenticated) {
      return null;
    }
    if (BillingService().ticketCount > 0) {
      return null;
    }
    return BillingService().meStatus?.remainingCount;
  }

  String _dailyCountKeyForUser(String? userId) {
    if (userId != null) {
      return '${_dailyUsedCountKey}_$userId';
    }
    return _dailyUsedCountKey;
  }

  String _dailyKeyForUser(String? userId) {
    if (userId != null) {
      return '${_dailyKeyKey}_$userId';
    }
    return _dailyKeyKey;
  }

  Future<void> _migrateLegacyDailyUsageIfNeeded(
    SharedPreferences prefs,
    String? userId,
  ) async {
    if (_legacyMigrationDone) {
      return;
    }

    final unifiedKey = _dailyKeyForUser(userId);
    final unifiedCountKey = _dailyCountKeyForUser(userId);
    if (prefs.containsKey(unifiedKey) || prefs.containsKey(unifiedCountKey)) {
      _legacyMigrationDone = true;
      return;
    }

    final legacyDayKey = resolveLegacyDailyKey(
      userId: userId,
      readString: prefs.getString,
    );
    if (legacyDayKey == null) {
      _legacyMigrationDone = true;
      return;
    }

    final legacyCount = resolveLegacyDailyCount(
      userId: userId,
      storedKey: legacyDayKey,
      readString: prefs.getString,
      readInt: prefs.getInt,
    );

    await prefs.setString(unifiedKey, legacyDayKey);
    await prefs.setInt(unifiedCountKey, legacyCount);

    for (final bucket in const ['pro', 'free']) {
      final legacyKey = userId != null
          ? '${_dailyKeyKey}_${userId}_$bucket'
          : '${_dailyKeyKey}_$bucket';
      final legacyCountKey = userId != null
          ? '${_dailyUsedCountKey}_${userId}_$bucket'
          : '${_dailyUsedCountKey}_$bucket';
      unawaited(prefs.remove(legacyKey));
      unawaited(prefs.remove(legacyCountKey));
    }

    _legacyMigrationDone = true;
  }

  UserMode _effectiveMode() {
    if (!_authService.isAuthenticated) {
      return UserMode.guest;
    }
    if (BillingService().hasActiveSubscription) {
      return UserMode.pro;
    }
    return UserMode.free;
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
