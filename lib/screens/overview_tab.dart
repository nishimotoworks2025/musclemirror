import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/muscle_data.dart';
import '../theme/app_theme.dart';

class OverviewTab extends StatefulWidget {
  final MuscleEvaluation? evaluation;
  final EvaluationType evaluationType;
  final List<MuscleEvaluation> evaluations;

  const OverviewTab({
    super.key,
    this.evaluation,
    required this.evaluationType,
    required this.evaluations,
  });

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  int? _comparisonIndex;

  MuscleEvaluation? get _currentEvaluation => widget.evaluation;

  MuscleEvaluation? get _comparisonEvaluation {
    if (_comparisonIndex == null) return null;
    if (_comparisonIndex! < 0 || _comparisonIndex! >= widget.evaluations.length) {
      return null;
    }
    return widget.evaluations[_comparisonIndex!];
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy/MM/dd HH:mm').format(date);
  }

  int _scoreToTopPercent(double score) {
    if (score >= 9.5) return 1;
    if (score >= 8.5) return 3;
    if (score >= 7.5) return 8;
    if (score >= 6.5) return 20;
    if (score >= 5.5) return 40;
    if (score >= 4.0) return 60;
    if (score >= 3.0) return 80;
    return 95;
  }

  void _goToPreviousComparison() {
    setState(() {
      if (_comparisonIndex == null) {
        if (widget.evaluations.length >= 2) {
          _comparisonIndex = widget.evaluations.length - 2;
        }
      } else if (_comparisonIndex! > 0) {
        _comparisonIndex = _comparisonIndex! - 1;
      }
    });
  }

  void _goToNextComparison() {
    setState(() {
      if (_comparisonIndex == null) return;
      if (_comparisonIndex! < widget.evaluations.length - 2) {
        _comparisonIndex = _comparisonIndex! + 1;
      } else {
        _comparisonIndex = null;
      }
    });
  }

  void _clearComparison() {
    setState(() {
      _comparisonIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentEval = _currentEvaluation;
    if (currentEval == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('判定を開始してください', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final comparisonEval = _comparisonEvaluation;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EvaluationModeBadge(type: currentEval.evaluationType),
          const SizedBox(height: 12),
          _PercentileBadge(topPercent: _scoreToTopPercent(currentEval.totalScore)),
          const SizedBox(height: 12),
          _TotalScoreCard(
            score: currentEval.totalScore,
            comparisonScore: comparisonEval?.totalScore,
          ),
          const SizedBox(height: 24),
          Text('全体評価', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _RadarChartCard(
            metrics: currentEval.overallMetrics,
            comparisonMetrics: comparisonEval?.overallMetrics,
          ),
          if (widget.evaluations.length >= 2) ...[
            const SizedBox(height: 16),
            _ComparisonNavigator(
              comparisonEval: comparisonEval,
              comparisonIndex: _comparisonIndex,
              totalCount: widget.evaluations.length,
              formatDate: _formatDate,
              onPrevious: _goToPreviousComparison,
              onNext: _goToNextComparison,
              onClear: _clearComparison,
            ),
          ],
          const SizedBox(height: 24),
          Text('総合コメント', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _OverallCommentCard(comment: currentEval.overallComment),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _ComparisonNavigator extends StatelessWidget {
  final MuscleEvaluation? comparisonEval;
  final int? comparisonIndex;
  final int totalCount;
  final String Function(DateTime) formatDate;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClear;

  const _ComparisonNavigator({
    required this.comparisonEval,
    required this.comparisonIndex,
    required this.totalCount,
    required this.formatDate,
    required this.onPrevious,
    required this.onNext,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canGoPrevious = comparisonIndex == null ? totalCount >= 2 : comparisonIndex! > 0;
    final canGoNext = comparisonIndex != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: canGoPrevious ? onPrevious : null,
            icon: const Icon(Icons.chevron_left),
            tooltip: '前のデータと比較',
          ),
          Expanded(
            child: Column(
              children: [
                if (comparisonEval == null)
                  Text(
                    '比較なし',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                    textAlign: TextAlign.center,
                  )
                else ...[
                  Text(
                    '比較: ${formatDate(comparisonEval!.evaluatedAt)}',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: onClear,
                    child: Text(
                      '比較を解除',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: canGoNext ? onNext : null,
            icon: const Icon(Icons.chevron_right),
            tooltip: '次のデータと比較',
          ),
        ],
      ),
    );
  }
}

class _TotalScoreCard extends StatelessWidget {
  final double score;
  final double? comparisonScore;

  const _TotalScoreCard({
    required this.score,
    this.comparisonScore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scoreColor = AppTheme.getScoreColor(score);
    final diff = comparisonScore == null ? null : score - comparisonScore!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('総合スコア', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '10点満点の評価',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withAlpha(150),
                    ),
                  ),
                  if (diff != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          diff > 0
                              ? Icons.arrow_upward
                              : diff < 0
                                  ? Icons.arrow_downward
                                  : Icons.remove,
                          size: 16,
                          color: diff > 0
                              ? AppTheme.scoreExcellent
                              : diff < 0
                                  ? AppTheme.scorePoor
                                  : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)} vs 比較データ',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: diff > 0
                                ? AppTheme.scoreExcellent
                                : diff < 0
                                    ? AppTheme.scorePoor
                                    : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: scoreColor, width: 4),
              ),
              child: Center(
                child: Text(
                  score.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: scoreColor,
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

class _RadarChartCard extends StatelessWidget {
  final OverallMetrics metrics;
  final OverallMetrics? comparisonMetrics;

  const _RadarChartCard({
    required this.metrics,
    this.comparisonMetrics,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final dataSets = <RadarDataSet>[
      RadarDataSet(
        dataEntries: List.generate(5, (_) => const RadarEntry(value: 0)),
        fillColor: Colors.transparent,
        borderColor: Colors.transparent,
        entryRadius: 0,
      ),
      RadarDataSet(
        dataEntries: List.generate(5, (_) => const RadarEntry(value: 10)),
        fillColor: Colors.transparent,
        borderColor: Colors.transparent,
        entryRadius: 0,
      ),
    ];

    if (comparisonMetrics != null) {
      dataSets.add(
        RadarDataSet(
          dataEntries: [
            RadarEntry(value: comparisonMetrics!.volume),
            RadarEntry(value: comparisonMetrics!.definition),
            RadarEntry(value: comparisonMetrics!.balance),
            RadarEntry(value: comparisonMetrics!.leanness),
            RadarEntry(value: comparisonMetrics!.posture),
          ],
          fillColor: Colors.grey.withAlpha(25),
          borderColor: Colors.grey,
          borderWidth: 1,
          entryRadius: 2,
        ),
      );
    }

    dataSets.add(
      RadarDataSet(
        dataEntries: [
          RadarEntry(value: metrics.volume),
          RadarEntry(value: metrics.definition),
          RadarEntry(value: metrics.balance),
          RadarEntry(value: metrics.leanness),
          RadarEntry(value: metrics.posture),
        ],
        fillColor: AppTheme.brandBlue.withAlpha(50),
        borderColor: AppTheme.brandBlue,
        borderWidth: 2,
        entryRadius: 3,
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              height: 280,
              child: RadarChart(
                RadarChartData(
                  radarShape: RadarShape.circle,
                  dataSets: dataSets,
                  radarBackgroundColor: Colors.transparent,
                  borderData: FlBorderData(show: false),
                  radarBorderData: BorderSide(
                    color: isDark ? Colors.white24 : Colors.black12,
                  ),
                  titlePositionPercentageOffset: 0.2,
                  titleTextStyle: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  getTitle: (index, angle) {
                    const titles = ['筋量', '定義感', 'バランス', '絞り', '姿勢'];
                    return RadarChartTitle(text: titles[index]);
                  },
                  tickCount: 5,
                  ticksTextStyle: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  tickBorderData: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  gridBorderData: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
              ),
            ),
            if (comparisonMetrics != null) ...[
              const SizedBox(height: 12),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LegendItem(color: AppTheme.brandBlue, label: '現在'),
                  SizedBox(width: 24),
                  _LegendItem(color: Colors.grey, label: '比較対象'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withAlpha(50),
            border: Border.all(color: color, width: 2),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _OverallCommentCard extends StatelessWidget {
  final String? comment;

  const _OverallCommentCard({this.comment});

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
                  '総合コメントがありません',
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
                const Icon(Icons.auto_awesome, color: AppTheme.brandBlue, size: 20),
                const SizedBox(width: 12),
                Text(
                  '分析コメント',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              comment!,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _PercentileBadge extends StatelessWidget {
  final int topPercent;

  const _PercentileBadge({required this.topPercent});

  Color _badgeColor() {
    if (topPercent <= 3) return const Color(0xFFFFD700);
    if (topPercent <= 8) return const Color(0xFFC0C0C0);
    if (topPercent <= 20) return const Color(0xFFCD7F32);
    return const Color(0xFF607D8B);
  }

  IconData _badgeIcon() {
    if (topPercent <= 3) return Icons.emoji_events;
    if (topPercent <= 20) return Icons.military_tech;
    return Icons.bar_chart;
  }

  @override
  Widget build(BuildContext context) {
    final color = _badgeColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withAlpha(180), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_badgeIcon(), size: 16, color: color),
          const SizedBox(width: 6),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '上位 ',
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(
                  text: '$topPercent%',
                  style: TextStyle(
                    fontSize: 15,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EvaluationModeBadge extends StatelessWidget {
  final EvaluationType type;

  const _EvaluationModeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final isPhysique = type == EvaluationType.physique;
    final color =
        isPhysique ? const Color(0xFFB23A48) : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPhysique ? Icons.local_fire_department : Icons.tune,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(
            '${type.label}モード',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            type.description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.color
                      ?.withAlpha(170),
                ),
          ),
        ],
      ),
    );
  }
}
