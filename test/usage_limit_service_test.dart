import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_mirror/services/usage_limit_service.dart';

void main() {
  group('UsageLimitService legacy migration', () {
    test('reads legacy free key for the same user', () {
      final store = <String, Object?>{
        '${UsageLimitService.dailyKeyKey}_user-1_free': '2026-03-21',
        '${UsageLimitService.dailyUsedCountKey}_user-1_free': 1,
      };

      final dayKey = resolveLegacyDailyKey(
        userId: 'user-1',
        readString: (key) => store[key] as String?,
      );
      final count = resolveLegacyDailyCount(
        userId: 'user-1',
        storedKey: dayKey,
        readString: (key) => store[key] as String?,
        readInt: (key) => store[key] as int?,
      );

      expect(dayKey, '2026-03-21');
      expect(count, 1);
    });

    test('uses the larger legacy count when both free and pro keys exist', () {
      final store = <String, Object?>{
        '${UsageLimitService.dailyKeyKey}_user-1_free': '2026-03-21',
        '${UsageLimitService.dailyUsedCountKey}_user-1_free': 1,
        '${UsageLimitService.dailyKeyKey}_user-1_pro': '2026-03-21',
        '${UsageLimitService.dailyUsedCountKey}_user-1_pro': 2,
      };

      final dayKey = resolveLegacyDailyKey(
        userId: 'user-1',
        readString: (key) => store[key] as String?,
      );
      final count = resolveLegacyDailyCount(
        userId: 'user-1',
        storedKey: dayKey,
        readString: (key) => store[key] as String?,
        readInt: (key) => store[key] as int?,
      );

      expect(dayKey, '2026-03-21');
      expect(count, 2);
    });

    test('does not mix another users legacy counters', () {
      final store = <String, Object?>{
        '${UsageLimitService.dailyKeyKey}_user-1_free': '2026-03-21',
        '${UsageLimitService.dailyUsedCountKey}_user-1_free': 1,
        '${UsageLimitService.dailyKeyKey}_user-2_pro': '2026-03-21',
        '${UsageLimitService.dailyUsedCountKey}_user-2_pro': 3,
      };

      final dayKey = resolveLegacyDailyKey(
        userId: 'user-1',
        readString: (key) => store[key] as String?,
      );
      final count = resolveLegacyDailyCount(
        userId: 'user-1',
        storedKey: dayKey,
        readString: (key) => store[key] as String?,
        readInt: (key) => store[key] as int?,
      );

      expect(dayKey, '2026-03-21');
      expect(count, 1);
    });
  });

  group('UsageLimitService free fallback', () {
    test(
      'treats same-day prior use as zero remaining after returning to free',
      () {
        final remaining = resolveFreeRemainingCount(
          localUsed: 0,
          serverUsedToday: 1,
        );

        expect(remaining, 0);
      },
    );

    test(
      'stays at one remaining when neither local nor server usage exists',
      () {
        final remaining = resolveFreeRemainingCount(
          localUsed: 0,
          serverUsedToday: 0,
        );

        expect(remaining, 1);
      },
    );

    test('prefers the larger of local and server usage counts', () {
      final remaining = resolveFreeRemainingCount(
        localUsed: 1,
        serverUsedToday: 0,
      );

      expect(remaining, 0);
    });
  });
}
