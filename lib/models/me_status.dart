import '../services/billing_service.dart';

/// Server-side user status model (ported from TrueSkin).
/// Represents the response from the /me API endpoint.
class MeStatus {
  static const Set<String> _terminalPlanStatuses = {
    'expired',
    'inactive',
    'revoked',
    'refunded',
  };

  final String planTier;
  final String effectivePlan;
  final String planStatus;
  final int remainingCount;
  final int dailyLimit;
  final int usedToday;
  final Map<String, bool> featureFlags;
  final String? expiresAt;

  MeStatus({
    required this.planTier,
    required this.effectivePlan,
    required this.planStatus,
    required this.remainingCount,
    required this.dailyLimit,
    required this.usedToday,
    required this.featureFlags,
    this.expiresAt,
  });

  DateTime? get expiresAtDate {
    final rawExpiresAt = expiresAt;
    if (rawExpiresAt == null || rawExpiresAt.isEmpty) {
      return null;
    }

    final parsed = DateTime.tryParse(rawExpiresAt);
    return parsed?.toUtc();
  }

  bool get isExpired {
    final expiry = expiresAtDate;
    if (expiry == null) {
      return false;
    }
    return !expiry.isAfter(DateTime.now().toUtc());
  }

  bool get hasProEntitlement {
    final isProPlan = planTier.toLowerCase() == 'pro' || 
                      effectivePlan.toLowerCase() == 'pro' ||
                      ProductIds.subscriptions.contains(effectivePlan.toLowerCase());
    if (!isProPlan) {
      return false;
    }

    if (isExpired) {
      return false;
    }

    if (_terminalPlanStatuses.contains(planStatus)) {
      return false;
    }

    // Cancellation should only preserve Pro while a future expiry is known.
    if (planStatus == 'cancelled' && expiresAtDate == null) {
      return false;
    }

    return true;
  }

  bool get isPro => hasProEntitlement;
  bool get isFree => !hasProEntitlement;
  String get resolvedEffectivePlan => hasProEntitlement ? 'pro' : 'free';

  factory MeStatus.fromJson(Map<String, dynamic> json) {
    final flags = json['feature_flags'];
    Map<String, bool> parsedFlags = {};
    if (flags is Map) {
      flags.forEach((key, value) {
        if (value is bool) {
          parsedFlags[key.toString()] = value;
        }
      });
    }

    final rawPlan = (json['plan'] as String? ?? 'free').toLowerCase();
    final rawEffectivePlan =
        (json['effective_plan'] as String? ?? json['plan'] as String? ?? 'free')
            .toLowerCase();

    return MeStatus(
      planTier: rawPlan,
      effectivePlan: rawEffectivePlan,
      planStatus: (json['plan_status'] as String? ?? 'none').toLowerCase(),
      remainingCount: json['remainingCount'] as int? ?? 0,
      dailyLimit: json['dailyLimit'] as int? ?? 1,
      usedToday: json['usedToday'] as int? ?? 0,
      featureFlags: parsedFlags,
      expiresAt: json['expires_at'] as String?,
    );
  }
}
