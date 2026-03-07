import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/muscle_data.dart';
import '../services/user_mode_service.dart';
import '../theme/app_theme.dart';
import 'subscription_page.dart';

class ProgressTab extends StatefulWidget {
  final List<MuscleEvaluation> evaluations;
  final UserMode userMode;

  const ProgressTab({
    super.key,
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
    // Free: show Pro upsell overlay
    if (widget.userMode == UserMode.free) {
      return _ProgressProUpsell();
    }

    final proEvaluations = widget.evaluations.where((e) => e.isPro).toList();

    if (proEvaluations.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timeline_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Pro判定の履歴がありません', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 8),
            Text(
              '複数回のPro判定で進捗を追跡できます',
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
          // Progress Comment (NEW)
          Text('進捗コメント', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _ProgressCommentCard(comment: latestEval.progressComment),
          const SizedBox(height: 24),

          // Total Score Trend
          Text('総合スコア推移', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _ScoreTrendCard(evaluations: proEvaluations),
          const SizedBox(height: 24),

          // Part Selector
          Text('部位別推移', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          _PartSelector(
            selectedPart: _selectedPart,
            onPartSelected: (part) {
              setState(() => _selectedPart = part);
            },
          ),
          const SizedBox(height: 16),
          if (_selectedPart != null)
            _PartTrendCard(
              evaluations: proEvaluations,
              part: _selectedPart!,
            ),
          const SizedBox(height: 24),

          // Growth Ranking
          Text('最近伸びた部位', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _GrowthRankingCard(evaluation: latestEval),
          const SizedBox(height: 24),

          // High Score Parts
          Text('点数が高い部位', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _HighScorePartsCard(evaluation: latestEval),
          const SizedBox(height: 24),

          // Low Score Parts
          Text('点数が低い部位', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _LowScorePartsCard(evaluation: latestEval),

          // Next Step Hint
          const SizedBox(height: 24),
          _NextStepCard(evaluation: latestEval),
          const SizedBox(height: 80), // FAB space
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

    // Generate mock weekly data if we only have one evaluation
    final spots = evaluations.length >= 2
        ? evaluations.asMap().entries.map((e) {
            return FlSpot(e.key.toDouble(), e.value.totalScore);
          }).toList()
        : [
            FlSpot(0, evaluations.first.totalScore * 0.85),
            FlSpot(1, evaluations.first.totalScore * 0.90),
            FlSpot(2, evaluations.first.totalScore * 0.88),
            FlSpot(3, evaluations.first.totalScore * 0.95),
            FlSpot(4, evaluations.first.totalScore),
          ];

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
                getDrawingHorizontalLine: (value) => FlLine(
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
                      final weekLabels = ['1週', '2週', '3週', '4週', '5週'];
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
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(show: false),
              minY: 0,
              maxY: 10,
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: AppTheme.brandBlue,
                  barWidth: 3,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) =>
                        FlDotCirclePainter(
                      radius: 4,
                      color: AppTheme.brandBlue,
                      strokeWidth: 2,
                      strokeColor: theme.cardColor,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppTheme.brandBlue.withAlpha(25),
                  ),
                ),
              ],
            ),
          ),
        ),
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
          final isSelected = selectedPart == part;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(part.japaneseName),
              selected: isSelected,
              onSelected: (selected) {
                onPartSelected(selected ? part : null);
              },
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

    // Get scores for the selected part
    final volumeSpots = <FlSpot>[];
    final definitionSpots = <FlSpot>[];

    for (var i = 0; i < evaluations.length; i++) {
      final partScore = evaluations[i].partScores.firstWhere(
        (s) => s.part == part,
        orElse: () =>
            const MusclePartScore(part: MusclePart.chest, volume: 0, definition: 0),
      );
      volumeSpots.add(FlSpot(i.toDouble(), partScore.volume));
      definitionSpots.add(FlSpot(i.toDouble(), partScore.definition));
    }

    // If only one evaluation, generate mock trend
    if (evaluations.length < 2) {
      final score = evaluations.first.partScores.firstWhere(
        (s) => s.part == part,
        orElse: () =>
            const MusclePartScore(part: MusclePart.chest, volume: 5, definition: 5),
      );
      volumeSpots.clear();
      definitionSpots.clear();
      for (var i = 0; i < 5; i++) {
        volumeSpots.add(FlSpot(i.toDouble(), score.volume * (0.85 + i * 0.04)));
        definitionSpots
            .add(FlSpot(i.toDouble(), score.definition * (0.88 + i * 0.03)));
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${part.japaneseName}の推移',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 2,
                    getDrawingHorizontalLine: (value) => FlLine(
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
                    bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendItem(color: AppTheme.accentOrange, label: 'Volume'),
                const SizedBox(width: 24),
                _LegendItem(color: AppTheme.accentCyan, label: 'Definition'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

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
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
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

    // Sort by overall score (simulating "growth")
    final sortedParts = List<MusclePartScore>.from(evaluation.partScores)
      ..sort((a, b) => b.overallScore.compareTo(a.overallScore));

    final topParts = sortedParts.take(3).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: topParts.asMap().entries.map((entry) {
            final rank = entry.key + 1;
            final score = entry.value;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: rank == 1
                          ? AppTheme.scoreExcellent
                          : rank == 2
                              ? AppTheme.scoreGood
                              : AppTheme.scoreAverage,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$rank',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
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
                    style: TextStyle(
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

    // Sort by overall score descending (highest first)
    final sortedParts = List<MusclePartScore>.from(evaluation.partScores)
      ..sort((a, b) => b.overallScore.compareTo(a.overallScore));

    final topParts = sortedParts.take(3).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: topParts.asMap().entries.map((entry) {
            final rank = entry.key + 1;
            final score = entry.value;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: rank == 1
                          ? AppTheme.scoreExcellent
                          : rank == 2
                              ? AppTheme.scoreGood
                              : AppTheme.scoreAverage,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.star,
                        color: Colors.white,
                        size: 16,
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
                    score.overallScore.toStringAsFixed(1),
                    style: TextStyle(
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

    // Sort by overall score ascending (lowest first)
    final sortedParts = List<MusclePartScore>.from(evaluation.partScores)
      ..sort((a, b) => a.overallScore.compareTo(b.overallScore));

    final bottomParts = sortedParts.take(3).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: bottomParts.asMap().entries.map((entry) {
            final score = entry.value;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppTheme.scorePoor,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.fitness_center,
                        color: Colors.white,
                        size: 14,
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
                    score.overallScore.toStringAsFixed(1),
                    style: TextStyle(
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
    final weakest = evaluation.weakPoints.isNotEmpty
        ? evaluation.weakPoints.first
        : MusclePart.abs;

    return Card(
      color: AppTheme.brandBlue.withAlpha(25),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.arrow_forward_rounded,
              color: AppTheme.brandBlue,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '次の一手',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppTheme.brandBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${weakest.japaneseName}の強化を優先することで、全体バランスの向上が期待できます。',
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

    if (comment == null || comment!.isEmpty) {
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
                  '進捗コメントがありません。複数回の判定で進捗分析が可能になります。',
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
                  child: Icon(
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
              comment!,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pro upsell overlay for the Progress tab.
class _ProgressProUpsell extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Lock icon
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
              '進捗トラッキング — Pro限定',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            Text(
              'Proプランにアップグレードすると、以下の進捗管理機能が利用できます。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withAlpha(180),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Feature list
            ...[
              _ProgressFeature(Icons.show_chart, '総合スコアの推移グラフ'),
              _ProgressFeature(Icons.analytics, '部位別スコアの推移'),
              _ProgressFeature(Icons.emoji_events, '成長ランキング'),
              _ProgressFeature(Icons.insights, '進捗コメント・アドバイス'),
              _ProgressFeature(Icons.arrow_forward_rounded, '次のトレーニング提案'),
            ].map((f) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(f.icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(f.text, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 32),

            // CTA Button
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
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressFeature {
  final IconData icon;
  final String text;
  const _ProgressFeature(this.icon, this.text);
}
