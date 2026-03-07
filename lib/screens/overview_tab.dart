import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
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
  int? _comparisonIndex; // null=比較なし, インデックス=比較対象

  MuscleEvaluation? get _currentEvaluation {
    if (widget.evaluations.isEmpty) return widget.evaluation;
    return widget.evaluations.last;
  }

  MuscleEvaluation? get _comparisonEvaluation {
    if (_comparisonIndex == null || widget.evaluations.isEmpty) return null;
    if (_comparisonIndex! < 0 || _comparisonIndex! >= widget.evaluations.length) return null;
    return widget.evaluations[_comparisonIndex!];
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy/MM/dd HH:mm').format(date);
  }

  /// スコア(0-10)を「上位X%」に変換する固定マッピング。
  /// 一般男性の体型分布を想定した経験的テーブル。
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
        // 比較なし→最新の1つ前
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
        // 最新の1つ前を超えたら比較なしに戻す
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
    final metrics = currentEval.overallMetrics;
    final comparisonEval = _comparisonEvaluation;
    final hasMultipleEvaluations = widget.evaluations.length >= 2;

    final topPercent = _scoreToTopPercent(currentEval.totalScore);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Percentile Badge (top-left)
          _PercentileBadge(topPercent: topPercent),
          const SizedBox(height: 12),

          // Total Score Card
          _TotalScoreCard(
            score: currentEval.totalScore,
            comparisonScore: comparisonEval?.totalScore,
          ),
          const SizedBox(height: 24),

          // Radar Chart
          Text('全体指標', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _RadarChartCard(
            metrics: metrics,
            comparisonMetrics: comparisonEval?.overallMetrics,
          ),
          
          // Comparison Navigator (below chart)
          if (hasMultipleEvaluations) ...[
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

          // Overall Comment
          Text('総合コメント', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _OverallCommentCard(comment: currentEval.overallComment),
          const SizedBox(height: 80), // FAB space
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
    final canGoPrevious = comparisonIndex == null 
        ? totalCount >= 2 
        : comparisonIndex! > 0;
    final canGoNext = comparisonIndex != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Previous button
          IconButton(
            onPressed: canGoPrevious ? onPrevious : null,
            icon: const Icon(Icons.chevron_left),
            tooltip: '前のデータと比較',
          ),
          
          // Status display
          Expanded(
            child: Column(
              children: [
                if (comparisonEval == null)
                  Text(
                    '比較なし',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                    ),
                    textAlign: TextAlign.center,
                  )
                else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.grey.withAlpha(100),
                          border: Border.all(color: Colors.grey, width: 2),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '比較: ${formatDate(comparisonEval!.evaluatedAt)}',
                          style: theme.textTheme.bodySmall,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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
          
          // Next button
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
    final diff = comparisonScore != null ? score - comparisonScore! : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '総合スコア',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '理想体型への到達度',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withAlpha(150),
                    ),
                  ),
                  if (diff != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          diff > 0 ? Icons.arrow_upward : diff < 0 ? Icons.arrow_downward : Icons.remove,
                          size: 16,
                          color: diff > 0 ? AppTheme.scoreExcellent : diff < 0 ? AppTheme.scorePoor : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)} vs 比較データ',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: diff > 0 ? AppTheme.scoreExcellent : diff < 0 ? AppTheme.scorePoor : Colors.grey,
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
                border: Border.all(
                  color: scoreColor,
                  width: 4,
                ),
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
      // Invisible min data set for 0 baseline
      RadarDataSet(
        dataEntries: [
          const RadarEntry(value: 0),
          const RadarEntry(value: 0),
          const RadarEntry(value: 0),
          const RadarEntry(value: 0),
          const RadarEntry(value: 0),
        ],
        fillColor: Colors.transparent,
        borderColor: Colors.transparent,
        entryRadius: 0,
      ),
      // Invisible max data set for scale (10)
      RadarDataSet(
        dataEntries: [
          const RadarEntry(value: 10),
          const RadarEntry(value: 10),
          const RadarEntry(value: 10),
          const RadarEntry(value: 10),
          const RadarEntry(value: 10),
        ],
        fillColor: Colors.transparent,
        borderColor: Colors.transparent,
        entryRadius: 0,
      ),
    ];

    // Add comparison data first (background)
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

    // Add current data (foreground)
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
                    switch (index) {
                      case 0:
                        return RadarChartTitle(text: '量感');
                      case 1:
                        return RadarChartTitle(text: '定義');
                      case 2:
                        return RadarChartTitle(text: 'バランス');
                      case 3:
                        return RadarChartTitle(text: '絞り');
                      case 4:
                        return RadarChartTitle(text: '姿勢');
                      default:
                        return const RadarChartTitle(text: '');
                    }
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
            // Legend for current data
            if (comparisonMetrics != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LegendItem(color: AppTheme.brandBlue, label: '現在'),
                  const SizedBox(width: 24),
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

  const _LegendItem({required this.color, required this.label});

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
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
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
                Icon(
                  Icons.auto_awesome,
                  color: AppTheme.brandBlue,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  '判定結果',
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

/// 「上位X%」パーセンタイルバッジ
class _PercentileBadge extends StatelessWidget {
  final int topPercent;

  const _PercentileBadge({required this.topPercent});

  Color _badgeColor() {
    if (topPercent <= 3) return const Color(0xFFFFD700);  // Gold
    if (topPercent <= 8) return const Color(0xFFC0C0C0);  // Silver
    if (topPercent <= 20) return const Color(0xFFCD7F32); // Bronze
    return const Color(0xFF607D8B);                        // Blue Grey
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
