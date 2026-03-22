import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/muscle_data.dart';
import '../services/user_mode_service.dart';
import '../theme/app_theme.dart';
import 'subscription_page.dart';

class ProgressTab extends StatefulWidget {
  final MuscleEvaluation? evaluation;
  final List<MuscleEvaluation> evaluations;
  final UserMode userMode;

  const ProgressTab({
    super.key,
    this.evaluation,
    required this.evaluations,
    required this.userMode,
  });

  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<ProgressTab> {
  MusclePart? _selectedPart;

  @override
  Widget build(BuildContext context) {
    if (widget.evaluation == null || !widget.evaluation!.isPro) {
      return const _ProgressProUpsell();
    }

    final proEvaluations = widget.evaluations.where((e) => e.isPro).toList();
    if (proEvaluations.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timeline_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Pro履歴がありません', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 8),
            Text(
              '複数回のPro判定で進捗を確認できます。',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final latestEval = proEvaluations.last;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('進捗コメント', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _ProgressCommentCard(comment: latestEval.progressComment),
          const SizedBox(height: 24),
          Text('総合スコア推移', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _ScoreTrendCard(evaluations: proEvaluations),
          const SizedBox(height: 24),
          Text('部位別推移', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          _PartSelector(
            selectedPart: _selectedPart,
            onPartSelected: (part) {
              setState(() => _selectedPart = part);
            },
          ),
          if (_selectedPart != null) ...[
            const SizedBox(height: 16),
            _PartTrendCard(
              evaluations: proEvaluations,
              part: _selectedPart!,
            ),
          ],
          const SizedBox(height: 24),
          Text('最も伸びた部位', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _GrowthRankingCard(evaluation: latestEval),
          const SizedBox(height: 24),
          Text('高スコア部位', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _HighScorePartsCard(evaluation: latestEval),
          const SizedBox(height: 24),
          Text('低スコア部位', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _LowScorePartsCard(evaluation: latestEval),
          const SizedBox(height: 24),
          _NextStepCard(evaluation: latestEval),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _ScoreTrendCard extends StatelessWidget {
  final List<MuscleEvaluation> evaluations;

  const _ScoreTrendCard({required this.evaluations});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chartEvaluations = evaluations.length >= 2
        ? evaluations
        : [
            evaluations.first.copyWith(
              evaluatedAt: evaluations.first.evaluatedAt.subtract(
                const Duration(days: 28),
              ),
              evaluationType: evaluations.first.evaluationType,
            ),
            evaluations.first.copyWith(
              evaluatedAt: evaluations.first.evaluatedAt.subtract(
                const Duration(days: 21),
              ),
              overallMetrics: OverallMetrics(
                volume: evaluations.first.overallMetrics.volume * 0.9,
                definition: evaluations.first.overallMetrics.definition * 0.9,
                balance: evaluations.first.overallMetrics.balance * 0.9,
                leanness: evaluations.first.overallMetrics.leanness * 0.9,
                posture: evaluations.first.overallMetrics.posture * 0.95,
              ),
            ),
            evaluations.first.copyWith(
              evaluatedAt: evaluations.first.evaluatedAt.subtract(
                const Duration(days: 14),
              ),
              overallMetrics: OverallMetrics(
                volume: evaluations.first.overallMetrics.volume * 0.92,
                definition: evaluations.first.overallMetrics.definition * 0.88,
                balance: evaluations.first.overallMetrics.balance * 0.9,
                leanness: evaluations.first.overallMetrics.leanness * 0.93,
                posture: evaluations.first.overallMetrics.posture * 0.96,
              ),
            ),
            evaluations.first.copyWith(
              evaluatedAt: evaluations.first.evaluatedAt.subtract(
                const Duration(days: 7),
              ),
              overallMetrics: OverallMetrics(
                volume: evaluations.first.overallMetrics.volume * 0.96,
                definition: evaluations.first.overallMetrics.definition * 0.95,
                balance: evaluations.first.overallMetrics.balance * 0.95,
                leanness: evaluations.first.overallMetrics.leanness * 0.96,
                posture: evaluations.first.overallMetrics.posture * 0.98,
              ),
            ),
            evaluations.first,
          ];
    final lineBars = _buildModeTrendLines(chartEvaluations, theme.cardColor);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 2,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: isDark ? Colors.white12 : Colors.black12,
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: 2,
                    getTitlesWidget: (value, meta) => Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      const weekLabels = ['1週', '2週', '3週', '4週', '5週'];
                      final idx = value.toInt();
                      if (idx >= 0 && idx < weekLabels.length) {
                        return Text(
                          weekLabels[idx],
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              minY: 0,
              maxY: 10,
              lineBarsData: lineBars,
            ),
          ),
        ),
      ),
    );
  }

  List<LineChartBarData> _buildModeTrendLines(
    List<MuscleEvaluation> values,
    Color cardColor,
  ) {
    final segments = <LineChartBarData>[];
    var currentSpots = <FlSpot>[];
    EvaluationType? currentType;

    for (var i = 0; i < values.length; i++) {
      final evaluation = values[i];
      final spot = FlSpot(i.toDouble(), evaluation.totalScore);
      final type = evaluation.evaluationType;

      if (currentType == null) {
        currentType = type;
        currentSpots.add(spot);
        continue;
      }

      if (type == currentType) {
        currentSpots.add(spot);
        continue;
      }

      currentSpots.add(spot);
      segments.add(_lineForType(currentSpots, currentType, cardColor));
      currentType = type;
      currentSpots = [
        FlSpot((i - 1).toDouble(), values[i - 1].totalScore),
        spot,
      ];
    }

    if (currentType != null && currentSpots.isNotEmpty) {
      segments.add(_lineForType(currentSpots, currentType, cardColor));
    }

    return segments;
  }

  LineChartBarData _lineForType(
    List<FlSpot> spots,
    EvaluationType type,
    Color cardColor,
  ) {
    final color = type == EvaluationType.physique
        ? const Color(0xFFB23A48)
        : AppTheme.brandBlue;
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 3,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
          radius: 4,
          color: color,
          strokeWidth: 2,
          strokeColor: cardColor,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        color: color.withAlpha(25),
      ),
    );
  }
}

class _PartSelector extends StatelessWidget {
  final MusclePart? selectedPart;
  final void Function(MusclePart?) onPartSelected;

  const _PartSelector({
    required this.selectedPart,
    required this.onPartSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: MusclePart.values.map((part) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(part.japaneseName),
              selected: selectedPart == part,
              onSelected: (selected) => onPartSelected(selected ? part : null),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PartTrendCard extends StatelessWidget {
  final List<MuscleEvaluation> evaluations;
  final MusclePart part;

  const _PartTrendCard({
    required this.evaluations,
    required this.part,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final volumeSpots = <FlSpot>[];
    final definitionSpots = <FlSpot>[];

    for (var i = 0; i < evaluations.length; i++) {
      final partScore = evaluations[i].partScores.firstWhere(
        (s) => s.part == part,
        orElse: () => const MusclePartScore(
          part: MusclePart.chest,
          volume: 0,
          definition: 0,
        ),
      );
      volumeSpots.add(FlSpot(i.toDouble(), partScore.volume));
      definitionSpots.add(FlSpot(i.toDouble(), partScore.definition));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${part.japaneseName}の推移', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 2,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: isDark ? Colors.white12 : Colors.black12,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: 2,
                        getTitlesWidget: (value, meta) => Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  minY: 0,
                  maxY: 10,
                  lineBarsData: [
                    LineChartBarData(
                      spots: volumeSpots,
                      isCurved: true,
                      color: AppTheme.accentOrange,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: definitionSpots,
                      isCurved: true,
                      color: AppTheme.accentCyan,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LineLegendItem(color: AppTheme.accentOrange, label: 'Volume'),
                SizedBox(width: 24),
                _LineLegendItem(color: AppTheme.accentCyan, label: 'Definition'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LineLegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LineLegendItem({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _GrowthRankingCard extends StatelessWidget {
  final MuscleEvaluation evaluation;

  const _GrowthRankingCard({required this.evaluation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedParts = List<MusclePartScore>.from(evaluation.partScores)
      ..sort((a, b) => b.overallScore.compareTo(a.overallScore));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: sortedParts.take(3).toList().asMap().entries.map((entry) {
            final rank = entry.key + 1;
            final score = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: rank == 1
                        ? AppTheme.scoreExcellent
                        : rank == 2
                            ? AppTheme.scoreGood
                            : AppTheme.scoreAverage,
                    child: Text(
                      '$rank',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      score.part.japaneseName,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    '+${(score.overallScore * 0.1).toStringAsFixed(1)}',
                    style: const TextStyle(
                      color: AppTheme.scoreExcellent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _HighScorePartsCard extends StatelessWidget {
  final MuscleEvaluation evaluation;

  const _HighScorePartsCard({required this.evaluation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedParts = List<MusclePartScore>.from(evaluation.partScores)
      ..sort((a, b) => b.overallScore.compareTo(a.overallScore));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: sortedParts.take(3).map((score) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.star, color: AppTheme.scoreExcellent),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      score.part.japaneseName,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    score.overallScore.toStringAsFixed(1),
                    style: const TextStyle(
                      color: AppTheme.scoreExcellent,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _LowScorePartsCard extends StatelessWidget {
  final MuscleEvaluation evaluation;

  const _LowScorePartsCard({required this.evaluation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedParts = List<MusclePartScore>.from(evaluation.partScores)
      ..sort((a, b) => a.overallScore.compareTo(b.overallScore));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: sortedParts.take(3).map((score) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.fitness_center, color: AppTheme.scorePoor),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      score.part.japaneseName,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    score.overallScore.toStringAsFixed(1),
                    style: const TextStyle(
                      color: AppTheme.scorePoor,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _NextStepCard extends StatelessWidget {
  final MuscleEvaluation evaluation;

  const _NextStepCard({required this.evaluation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weakest =
        evaluation.weakPoints.isNotEmpty ? evaluation.weakPoints.first : MusclePart.abs;

    return Card(
      color: AppTheme.brandBlue.withAlpha(25),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.arrow_forward_rounded, color: AppTheme.brandBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '次の一歩',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppTheme.brandBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${weakest.japaneseName}の強化を意識すると、全身バランスの改善が期待できます。',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressCommentCard extends StatelessWidget {
  final String? comment;

  const _ProgressCommentCard({this.comment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = comment ?? '';

    if (value.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: theme.colorScheme.onSurface.withAlpha(100),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '進捗コメントがありません。複数回のPro判定で進捗分析が利用可能になります。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodyMedium?.color?.withAlpha(150),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.scoreExcellent.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.trending_up,
                    color: AppTheme.scoreExcellent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '進捗分析',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressProUpsell extends StatelessWidget {
  const _ProgressProUpsell();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.amber.shade400,
                    Colors.amber.shade700,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withAlpha(60),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.lock_outline,
                color: Colors.white,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '進捗トラッキング - Pro限定',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Proプランにアップグレードすると、過去の進捗確認機能が利用できます。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withAlpha(180),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ...const [
              (Icons.show_chart, '総合スコアの推移グラフ'),
              (Icons.analytics, '部位別スコアの推移'),
              (Icons.emoji_events, '成長ランキング'),
              (Icons.insights, '進捗コメントのアドバイス'),
              (Icons.arrow_forward_rounded, '次のトレーニング提案'),
            ].map((item) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(item.$1, size: 20, color: AppTheme.brandBlue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(item.$2, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SubscriptionPage()),
                  );
                },
                icon: const Icon(Icons.workspace_premium),
                label: const Text('Proプランにアップグレード'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
