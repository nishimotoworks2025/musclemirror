import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/muscle_data.dart';
import '../theme/app_theme.dart';

class HistoryTab extends StatelessWidget {
  final List<MuscleEvaluation> evaluations;
  final void Function(int index)? onEvaluationSelected;
  final void Function(int index)? onEvaluationDeleted;

  const HistoryTab({
    super.key,
    required this.evaluations,
    this.onEvaluationSelected,
    this.onEvaluationDeleted,
  });

  @override
  Widget build(BuildContext context) {
    if (evaluations.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('履歴がありません', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 8),
            Text(
              '判定を行うと履歴が記録されます',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    // Sort by date, newest first
    final sortedEvaluations = List<MuscleEvaluation>.from(evaluations)
      ..sort((a, b) => b.evaluatedAt.compareTo(a.evaluatedAt));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: sortedEvaluations.length,
      itemBuilder: (context, index) {
        final evaluation = sortedEvaluations[index];
        final originalIndex = evaluations.indexOf(evaluation);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _HistoryCard(
            evaluation: evaluation,
            onTap: () => onEvaluationSelected?.call(originalIndex),
            onDelete: () => _confirmDelete(context, originalIndex),
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('履歴を削除'),
        content: const Text('この判定結果を削除しますか？この操作は元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              onEvaluationDeleted?.call(index);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final MuscleEvaluation evaluation;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const _HistoryCard({
    required this.evaluation,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dateFormat = DateFormat('yyyy/MM/dd HH:mm');
    final scoreColor = AppTheme.getScoreColor(evaluation.totalScore);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 100,
          child: Row(
            children: [
              // Thumbnail image (left side)
              SizedBox(
                width: 100,
                height: 100,
                child: _buildThumbnail(isDark),
              ),
              // Info section (middle)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Date
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 14,
                            color: theme.textTheme.bodySmall?.color?.withAlpha(150),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            dateFormat.format(evaluation.evaluatedAt),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Score
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: scoreColor.withAlpha(25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: scoreColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '総合スコア: ${evaluation.totalScore.toStringAsFixed(1)}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: scoreColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Evaluation type
                      Text(
                        _getEvaluationTypeName(evaluation.evaluationType),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withAlpha(150),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Delete button (right side)
              IconButton(
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error.withAlpha(180),
                ),
                tooltip: '削除',
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  String _getEvaluationTypeName(EvaluationType type) {
    return switch (type) {
      EvaluationType.balanced => 'バランス重視',
      EvaluationType.muscleFocused => '筋量重視',
      EvaluationType.leanFocused => '絞り重視',
    };
  }

  Widget _buildThumbnail(bool isDark) {
    if (evaluation.imagePath != null && 
        File(evaluation.imagePath!).existsSync()) {
      return Image.file(
        File(evaluation.imagePath!),
        fit: BoxFit.cover,
      );
    }

    // Placeholder
    return Container(
      color: isDark ? Colors.grey[850] : Colors.grey[200],
      child: Center(
        child: Icon(
          Icons.fitness_center,
          size: 32,
          color: isDark ? Colors.white24 : Colors.black26,
        ),
      ),
    );
  }
}
