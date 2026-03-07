/// Data models for Muscle Mirror app.
library;

/// Evaluation type (ideal body standard).
enum EvaluationType {
  balanced,     // バランス重視
  muscleFocused, // 筋量重視
  leanFocused,  // 絞り重視
}

/// Pre-check result from Gemini 2.5 Flash-Lite.
enum PreCheckLevel {
  pass,  // PASS: 問題なし
  warn,  // WARN: 精度低下の可能性あり
  fail,  // FAIL: 再撮影要求
}

/// Pre-check response from the clothing/composition check.
class PreCheckResult {
  final PreCheckLevel level;
  final String reasonCode;

  const PreCheckResult({
    required this.level,
    required this.reasonCode,
  });

  factory PreCheckResult.fromJson(Map<String, dynamic> json) {
    return PreCheckResult(
      level: PreCheckLevel.values.firstWhere(
        (e) => e.name.toLowerCase() == (json['level'] as String).toLowerCase(),
        orElse: () => PreCheckLevel.fail,
      ),
      reasonCode: json['reason_code'] as String? ?? 'unknown',
    );
  }
}

/// Overall metrics for radar chart (5 axes).
class OverallMetrics {
  final double volume;      // 量感 (0-10)
  final double definition;  // 定義 (0-10)
  final double balance;     // 左右・部位バランス (0-10)
  final double leanness;    // 脂肪感の少なさ (0-10)
  final double posture;     // 姿勢 (0-10, 参考値)

  const OverallMetrics({
    required this.volume,
    required this.definition,
    required this.balance,
    required this.leanness,
    required this.posture,
  });

  double get totalScore {
    // Weighted average: posture has lower weight
    const postureWeight = 0.5;
    const otherWeight = 1.0;
    final total = (volume * otherWeight) +
        (definition * otherWeight) +
        (balance * otherWeight) +
        (leanness * otherWeight) +
        (posture * postureWeight);
    final weightSum = (otherWeight * 4) + postureWeight;
    final rawScore = total / weightSum;
    
    // Apply score boost for high scores (7.0+)
    // This compensates for Gemini's conservative scoring tendency
    return _boostHighScore(rawScore);
  }
  
  /// Boost high scores to compensate for LLM's conservative scoring.
  /// - Below 7.0: no change
  /// - 7.0-8.0: slight boost (+0.5 at 7.5)
  /// - 8.0-9.0: strong boost (+1.0 to +1.5) 
  /// - 9.0+: approaches 10
  static double _boostHighScore(double score) {
    if (score < 7.0) return score;
    
    if (score < 8.0) {
      // 7.0-8.0: boost by 0 to 1.0
      final t = (score - 7.0);  // 0.0 to 1.0
      return score + t;  // 7.0→7.0, 7.5→8.0, 8.0→9.0
    } else if (score < 9.0) {
      // 8.0-9.0: boost by 1.0 to 1.0 (already at +1.0 from 8.0=9.0)
      // 8.0→9.0, 8.5→9.5, 9.0→10.0
      final t = (score - 8.0);  // 0.0 to 1.0
      return 9.0 + t;
    } else {
      // 9.0+: already maxed
      return 10.0;
    }
  }

  factory OverallMetrics.fromJson(Map<String, dynamic> json) {
    return OverallMetrics(
      volume: (json['volume'] as num?)?.toDouble() ?? 0.0,
      definition: (json['definition'] as num?)?.toDouble() ?? 0.0,
      balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
      leanness: (json['leanness'] as num?)?.toDouble() ?? 0.0,
      posture: (json['posture'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'volume': volume,
        'definition': definition,
        'balance': balance,
        'leanness': leanness,
        'posture': posture,
      };
}

/// Muscle part enumeration (8 parts, front view).
enum MusclePart {
  shoulder,   // 肩
  chest,      // 胸
  arm,        // 腕
  forearm,    // 前腕
  abs,        // 腹
  leg,        // 脚
  calf,       // ふくらはぎ
  back,       // 背中（前面推定）
}

/// Extension to get Japanese labels for muscle parts.
extension MusclePartExtension on MusclePart {
  String get japaneseName {
    switch (this) {
      case MusclePart.shoulder:
        return '肩';
      case MusclePart.chest:
        return '胸';
      case MusclePart.arm:
        return '腕';
      case MusclePart.forearm:
        return '前腕';
      case MusclePart.abs:
        return '腹';
      case MusclePart.leg:
        return '脚';
      case MusclePart.calf:
        return 'ふくらはぎ';
      case MusclePart.back:
        return '背中';
    }
  }

  String get englishName {
    switch (this) {
      case MusclePart.shoulder:
        return 'Shoulder';
      case MusclePart.chest:
        return 'Chest';
      case MusclePart.arm:
        return 'Arm';
      case MusclePart.forearm:
        return 'Forearm';
      case MusclePart.abs:
        return 'Abs';
      case MusclePart.leg:
        return 'Leg';
      case MusclePart.calf:
        return 'Calf';
      case MusclePart.back:
        return 'Back';
    }
  }
}

/// Detailed score for a single muscle part.
class MusclePartScore {
  final MusclePart part;
  final double volume;      // 量感
  final double definition;  // 定義
  final double? symmetry;   // 左右差 (Pro only)
  final double? fatAppearance; // 脂肪感 (Pro only)

  const MusclePartScore({
    required this.part,
    required this.volume,
    required this.definition,
    this.symmetry,
    this.fatAppearance,
  });

  /// Overall score for this part (average of volume and definition).
  double get overallScore => (volume + definition) / 2;

  factory MusclePartScore.fromJson(Map<String, dynamic> json) {
    final partName = json['part'] as String;
    return MusclePartScore(
      part: MusclePart.values.firstWhere(
        (e) => e.name.toLowerCase() == partName.toLowerCase(),
        orElse: () => MusclePart.chest,
      ),
      volume: (json['volume'] as num?)?.toDouble() ?? 0.0,
      definition: (json['definition'] as num?)?.toDouble() ?? 0.0,
      symmetry: (json['symmetry'] as num?)?.toDouble(),
      fatAppearance: (json['fat_appearance'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'part': part.name,
        'volume': volume,
        'definition': definition,
        if (symmetry != null) 'symmetry': symmetry,
        if (fatAppearance != null) 'fat_appearance': fatAppearance,
      };
}

/// Complete muscle evaluation result.
class MuscleEvaluation {
  final DateTime evaluatedAt;
  final EvaluationType evaluationType;
  final OverallMetrics overallMetrics;
  final List<MusclePartScore> partScores;
  final List<MusclePart> weakPoints; // TOP 3 weak points
  
  // New fields for comments and image
  final String? overallComment;     // 総合コメント（概要タブ用）
  final Map<MusclePart, String>? partComments;  // 部位別コメント（詳細タブ用）
  final String? progressComment;    // 進捗コメント（進捗タブ用）
  final String? imagePath;          // 撮影画像のパス
  final bool isPro;                 // Proモードで測定されたか

  const MuscleEvaluation({
    required this.evaluatedAt,
    required this.evaluationType,
    required this.overallMetrics,
    required this.partScores,
    required this.weakPoints,
    this.overallComment,
    this.partComments,
    this.progressComment,
    this.imagePath,
    this.isPro = false,
  });

  double get totalScore => overallMetrics.totalScore;

  factory MuscleEvaluation.fromJson(Map<String, dynamic> json) {
    final partScoresJson = json['part_scores'] as List<dynamic>? ?? [];
    final weakPointsJson = json['weak_points'] as List<dynamic>? ?? [];
    
    // Parse part comments
    Map<MusclePart, String>? partComments;
    if (json['part_comments'] != null) {
      final commentsJson = json['part_comments'] as Map<String, dynamic>;
      partComments = {};
      commentsJson.forEach((key, value) {
        final part = MusclePart.values.firstWhere(
          (p) => p.name.toLowerCase() == key.toLowerCase(),
          orElse: () => MusclePart.chest,
        );
        partComments![part] = value as String;
      });
    }

    return MuscleEvaluation(
      evaluatedAt: DateTime.parse(
          json['evaluated_at'] as String? ?? DateTime.now().toIso8601String()),
      evaluationType: EvaluationType.values.firstWhere(
        (e) =>
            e.name.toLowerCase() ==
            (json['evaluation_type'] as String?)?.toLowerCase(),
        orElse: () => EvaluationType.balanced,
      ),
      overallMetrics: OverallMetrics.fromJson(
          json['overall_metrics'] as Map<String, dynamic>? ?? {}),
      partScores: partScoresJson
          .map((e) => MusclePartScore.fromJson(e as Map<String, dynamic>))
          .toList(),
      weakPoints: weakPointsJson
          .map((e) => MusclePart.values.firstWhere(
                (p) => p.name.toLowerCase() == (e as String).toLowerCase(),
                orElse: () => MusclePart.chest,
              ))
          .toList(),
      overallComment: json['overall_comment'] as String?,
      partComments: partComments,
      progressComment: json['progress_comment'] as String?,
      imagePath: json['image_path'] as String?,
      isPro: json['is_pro'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    // Convert part comments to serializable format
    Map<String, String>? partCommentsJson;
    if (partComments != null) {
      partCommentsJson = {};
      partComments!.forEach((key, value) {
        partCommentsJson![key.name] = value;
      });
    }
    
    return {
      'evaluated_at': evaluatedAt.toIso8601String(),
      'evaluation_type': evaluationType.name,
      'overall_metrics': overallMetrics.toJson(),
      'part_scores': partScores.map((e) => e.toJson()).toList(),
      'weak_points': weakPoints.map((e) => e.name).toList(),
      if (overallComment != null) 'overall_comment': overallComment,
      if (partCommentsJson != null) 'part_comments': partCommentsJson,
      if (progressComment != null) 'progress_comment': progressComment,
      if (imagePath != null) 'image_path': imagePath,
      'is_pro': isPro,
    };
  }

  /// Create a copy with updated fields.
  MuscleEvaluation copyWith({
    DateTime? evaluatedAt,
    EvaluationType? evaluationType,
    OverallMetrics? overallMetrics,
    List<MusclePartScore>? partScores,
    List<MusclePart>? weakPoints,
    String? overallComment,
    Map<MusclePart, String>? partComments,
    String? progressComment,
    String? imagePath,
    bool? isPro,
  }) {
    return MuscleEvaluation(
      evaluatedAt: evaluatedAt ?? this.evaluatedAt,
      evaluationType: evaluationType ?? this.evaluationType,
      overallMetrics: overallMetrics ?? this.overallMetrics,
      partScores: partScores ?? this.partScores,
      weakPoints: weakPoints ?? this.weakPoints,
      overallComment: overallComment ?? this.overallComment,
      partComments: partComments ?? this.partComments,
      progressComment: progressComment ?? this.progressComment,
      imagePath: imagePath ?? this.imagePath,
      isPro: isPro ?? this.isPro,
    );
  }

  /// Create a sample/mock evaluation for testing.
  factory MuscleEvaluation.sample() {
    return MuscleEvaluation(
      evaluatedAt: DateTime.now(),
      evaluationType: EvaluationType.balanced,
      overallMetrics: const OverallMetrics(
        volume: 6.5,
        definition: 5.8,
        balance: 7.2,
        leanness: 6.0,
        posture: 7.5,
      ),
      partScores: [
        const MusclePartScore(
            part: MusclePart.shoulder, volume: 7.0, definition: 6.5),
        const MusclePartScore(
            part: MusclePart.chest, volume: 6.0, definition: 5.5),
        const MusclePartScore(
            part: MusclePart.arm, volume: 7.5, definition: 6.8),
        const MusclePartScore(
            part: MusclePart.forearm, volume: 5.5, definition: 5.0),
        const MusclePartScore(
            part: MusclePart.abs, volume: 5.0, definition: 4.5),
        const MusclePartScore(
            part: MusclePart.leg, volume: 6.5, definition: 6.0),
        const MusclePartScore(
            part: MusclePart.calf, volume: 5.8, definition: 5.5),
        const MusclePartScore(
            part: MusclePart.back, volume: 6.2, definition: 5.8),
      ],
      weakPoints: [MusclePart.abs, MusclePart.forearm, MusclePart.calf],
      overallComment: '全体的にバランスの取れた体型です。特に肩と腕の発達が良好です。'
          '腹筋と前腕のトレーニングを強化することで、さらにバランスの良い体型を目指せます。',
      partComments: {
        MusclePart.shoulder: '肩の三角筋は良く発達しています。丸みのあるシルエットが形成されています。',
        MusclePart.chest: '大胸筋の発達は平均的です。インクラインプレスで上部を強化しましょう。',
        MusclePart.arm: '上腕二頭筋・三頭筋ともに良好な発達です。',
        MusclePart.forearm: '前腕は他の部位に比べてやや細めです。リストカールを追加しましょう。',
        MusclePart.abs: '腹直筋の輪郭がやや薄いです。体脂肪率を下げることで改善が期待できます。',
        MusclePart.leg: '大腿四頭筋は良好な発達です。ハムストリングスも意識しましょう。',
        MusclePart.calf: 'ふくらはぎはやや細めです。カーフレイズの頻度を上げましょう。',
        MusclePart.back: '背中の厚みは良好です。広背筋の広がりをさらに意識しましょう。',
      },
      progressComment: '前回の測定と比較して、肩と腕のスコアが向上しています。'
          '腹筋のトレーニングを継続することで、次回はさらに良い結果が期待できます。',
      isPro: true,
    );
  }
}
