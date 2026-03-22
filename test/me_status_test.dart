import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_mirror/models/me_status.dart';

void main() {
  group('MeStatus entitlement', () {
    test('keeps Pro during cancelled period until expiry', () {
      final futureExpiry = DateTime.now()
          .toUtc()
          .add(const Duration(days: 3))
          .toIso8601String();

      final status = MeStatus.fromJson({
        'plan': 'pro',
        'effective_plan': 'pro',
        'plan_status': 'cancelled',
        'expires_at': futureExpiry,
      });

      expect(status.isExpired, isFalse);
      expect(status.hasProEntitlement, isTrue);
      expect(status.isPro, isTrue);
      expect(status.resolvedEffectivePlan, 'pro');
    });

    test('falls back to Free after expiry even if API still says Pro', () {
      final pastExpiry = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 1))
          .toIso8601String();

      final status = MeStatus.fromJson({
        'plan': 'pro',
        'effective_plan': 'pro',
        'plan_status': 'cancelled',
        'expires_at': pastExpiry,
      });

      expect(status.isExpired, isTrue);
      expect(status.hasProEntitlement, isFalse);
      expect(status.isPro, isFalse);
      expect(status.isFree, isTrue);
      expect(status.resolvedEffectivePlan, 'free');
    });

    test('keeps Pro when tier is pro and expiry is still in the future', () {
      final futureExpiry = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 12))
          .toIso8601String();

      final status = MeStatus.fromJson({
        'plan': 'pro',
        'effective_plan': 'free',
        'plan_status': 'cancelled',
        'expires_at': futureExpiry,
      });

      expect(status.hasProEntitlement, isTrue);
      expect(status.resolvedEffectivePlan, 'pro');
    });

    test('stays Free without a Pro plan', () {
      final status = MeStatus.fromJson({
        'plan': 'free',
        'effective_plan': 'free',
        'plan_status': 'none',
      });

      expect(status.hasProEntitlement, isFalse);
      expect(status.isFree, isTrue);
      expect(status.resolvedEffectivePlan, 'free');
    });

    test('falls back to Free when cancelled has no expiry', () {
      final status = MeStatus.fromJson({
        'plan': 'pro',
        'effective_plan': 'pro',
        'plan_status': 'cancelled',
      });

      expect(status.hasProEntitlement, isFalse);
      expect(status.isFree, isTrue);
      expect(status.resolvedEffectivePlan, 'free');
    });
  });
}
