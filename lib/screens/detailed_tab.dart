import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/muscle_data.dart';
import '../services/pose_service.dart';
import '../services/user_mode_service.dart';
import '../theme/app_theme.dart';
import 'subscription_page.dart';

class DetailedTab extends StatefulWidget {
  final MuscleEvaluation? evaluation;
  final UserMode userMode;

  const DetailedTab({
    super.key,
    this.evaluation,
    required this.userMode,
  });

  @override
  State<DetailedTab> createState() => _DetailedTabState();
}

class _DetailedTabState extends State<DetailedTab> {
  MusclePart? _selectedPart;

  @override
  Widget build(BuildContext context) {
    bool canViewDetails = widget.evaluation?.isPro == true;

    // Free/Guest: show Pro upsell overlay if not in Pro mode AND the evaluation was not taken in Pro
    if (!canViewDetails) {
      return _ProUpsellOverlay(
        title: '詳細分析',
        description: 'Proプランにアップグレードすると、以下の詳細分析機能が利用できます。',
        features: const [
          _ProFeatureItem(icon: Icons.analytics, text: '部位別の詳細スコア（Volume / Definition）'),
          _ProFeatureItem(icon: Icons.straighten, text: '左右対称性の評価'),
          _ProFeatureItem(icon: Icons.visibility, text: '脂肪感の分析'),
          _ProFeatureItem(icon: Icons.touch_app, text: '部位タップで画像ハイライト'),
        ],
      );
    }

    if (widget.evaluation == null) {
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Captured Image with Highlight
          Text('撮影画像', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _CapturedImageViewer(
            imagePath: widget.evaluation!.imagePath,
            selectedPart: _selectedPart,
          ),
          const SizedBox(height: 24),

          // Muscle Part Scores and Comments (Combined)
          Text('部位別詳細評価', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _MuscleDetailedList(
            partScores: widget.evaluation!.partScores,
            partComments: widget.evaluation!.partComments,
            selectedPart: _selectedPart,
            onPartSelected: (part) {
              setState(() => _selectedPart = part);
            },
          ),

          // Selected Part Details (Pro features)
          if (_selectedPart != null) ...[
            const SizedBox(height: 24),
            _PartDetailsCard(
              partScore: widget.evaluation!.partScores.firstWhere(
                (s) => s.part == _selectedPart,
                orElse: () => const MusclePartScore(
                  part: MusclePart.chest,
                  volume: 0,
                  definition: 0,
                ),
              ),
              isPro: canViewDetails,
            ),
          ],
          const SizedBox(height: 80), // FAB space
        ],
      ),
    );
  }
}

/// Pro upsell overlay shown for Free/Guest users.
class _ProUpsellOverlay extends StatelessWidget {
  final String title;
  final String description;
  final List<_ProFeatureItem> features;

  const _ProUpsellOverlay({
    required this.title,
    required this.description,
    required this.features,
  });

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

            // Title
            Text(
              '$title - Pro限定',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Description
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withAlpha(180),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Feature list
            ...features.map((f) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(f.icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      f.text,
                      style: theme.textTheme.bodyMedium,
                    ),
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

class _ProFeatureItem {
  final IconData icon;
  final String text;
  const _ProFeatureItem({required this.icon, required this.text});
}

class _CapturedImageViewer extends StatefulWidget {
  final String? imagePath;
  final MusclePart? selectedPart;

  const _CapturedImageViewer({
    this.imagePath,
    this.selectedPart,
  });

  @override
  State<_CapturedImageViewer> createState() => _CapturedImageViewerState();
}

class _CapturedImageViewerState extends State<_CapturedImageViewer> with SingleTickerProviderStateMixin {
  BodyPartPolygons? _bodyParts;
  Size? _imageSize;
  Size? _displaySize;
  bool _isLoading = false;
  bool _detectionFailed = false;

  final TransformationController _transformationController = TransformationController();
  Animation<Matrix4>? _zoomAnimation;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addListener(() {
        if (_zoomAnimation != null) {
          _transformationController.value = _zoomAnimation!.value;
        }
      });
    _loadPoseData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _CapturedImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _loadPoseData();
    } else if (oldWidget.selectedPart != widget.selectedPart) {
      _zoomToSelectedPart();
    }
  }

  void _zoomToSelectedPart() {
    if (widget.selectedPart == null) {
      _animateZoom(Matrix4.identity());
      return;
    }

    if (_bodyParts == null || _imageSize == null || _displaySize == null) return;

    final polygons = _bodyParts!.getPolygonsForPart(widget.selectedPart!);
    if (polygons == null || polygons.isEmpty || !polygons.any((p) => p.isNotEmpty)) {
      _animateZoom(Matrix4.identity());
      return;
    }

    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;

    for (final poly in polygons) {
      for (final p in poly) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
    }

    final scaleX = _displaySize!.width / _imageSize!.width;
    final scaleY = _displaySize!.height / _imageSize!.height;
    final scale = (scaleX > scaleY) ? scaleX : scaleY;

    final scaledWidth = _imageSize!.width * scale;
    final scaledHeight = _imageSize!.height * scale;
    final offsetX = (_displaySize!.width - scaledWidth) / 2;
    final offsetY = (_displaySize!.height - scaledHeight) / 2;

    final dMinX = minX * scale + offsetX;
    final dMaxX = maxX * scale + offsetX;
    final dMinY = minY * scale + offsetY;
    final dMaxY = maxY * scale + offsetY;

    final rectWidth = dMaxX - dMinX;
    final rectHeight = dMaxY - dMinY;
    final rectCenterX = dMinX + rectWidth / 2;
    final rectCenterY = dMinY + rectHeight / 2;

    final padding = 60.0;
    final scaleXToFit = _displaySize!.width / (rectWidth + padding);
    final scaleYToFit = _displaySize!.height / (rectHeight + padding);
    final scaleToFit = scaleXToFit < scaleYToFit ? scaleXToFit : scaleYToFit;
    final targetScale = scaleToFit.clamp(1.2, 2.5);

    final tx = _displaySize!.width / 2 - rectCenterX * targetScale;
    final ty = _displaySize!.height / 2 - rectCenterY * targetScale;

    final maxTx = 0.0;
    final minTx = _displaySize!.width - _displaySize!.width * targetScale;
    final clampedTx = tx.clamp(minTx, maxTx);

    final maxTy = 0.0;
    final minTy = _displaySize!.height - _displaySize!.height * targetScale;
    final clampedTy = ty.clamp(minTy, maxTy);

    final matrix = Matrix4.identity()
      ..translate(clampedTx, clampedTy)
      ..scale(targetScale);

    _animateZoom(matrix);
  }

  void _animateZoom(Matrix4 targetMatrix) {
    _zoomAnimation = Matrix4Tween(
      begin: _transformationController.value,
      end: targetMatrix,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    _animationController.forward(from: 0);
  }

  Future<void> _loadPoseData() async {
    if (widget.imagePath == null || !File(widget.imagePath!).existsSync()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _detectionFailed = false;
    });

    try {
      // Get image dimensions
      final file = File(widget.imagePath!);
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final imgSize = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();

      // Detect pose
      final bodyParts = await PoseService().detectBodyParts(widget.imagePath!);

      if (mounted) {
        setState(() {
          _imageSize = imgSize;
          _bodyParts = bodyParts;
          _isLoading = false;
          _detectionFailed = bodyParts == null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _detectionFailed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 0.75,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _displaySize = Size(constraints.maxWidth, constraints.maxHeight);
            return Stack(
              fit: StackFit.expand,
              children: [
                InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Image or placeholder
                      if (widget.imagePath != null && File(widget.imagePath!).existsSync())
                        Image.file(
                          File(widget.imagePath!),
                          fit: BoxFit.cover,
                        )
                      else
                        Container(
                          color: isDark ? Colors.grey[850] : Colors.grey[200],
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.image_outlined,
                                size: 64,
                                color: isDark ? Colors.white38 : Colors.black26,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '撮影画像なし',
                                style: TextStyle(
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                            ],
                          ),
                        ),
                      
                    ],
                  ),
                ),
                
                // Loading indicator
                if (_isLoading)
                  Container(
                    color: Colors.black26,
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),

                // Selected Part Label (Static, above zoomable area)
                if (widget.selectedPart != null && !_isLoading)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 16,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(180),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.brandBlue, width: 1.5),
                        ),
                        child: Text(
                          widget.selectedPart!.japaneseName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                
                // Detection failed indicator (Static)
                if (_detectionFailed)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withAlpha(200),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber, size: 14, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'Pose未検出',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MuscleDetailedList extends StatelessWidget {
  final List<MusclePartScore> partScores;
  final Map<MusclePart, String>? partComments;
  final MusclePart? selectedPart;
  final void Function(MusclePart) onPartSelected;

  const _MuscleDetailedList({
    required this.partScores,
    this.partComments,
    this.selectedPart,
    required this.onPartSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Column(
        children: partScores.asMap().entries.map((entry) {
          final index = entry.key;
          final score = entry.value;
          final comment = partComments?[score.part];
          final isLast = index == partScores.length - 1;
          final isSelected = selectedPart == score.part;

          return Column(
            children: [
              InkWell(
                onTap: () => onPartSelected(score.part),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.brandBlue.withAlpha(20)
                        : Colors.transparent,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Score Badge
                      Center(
                        child: Text(
                          score.overallScore.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.getScoreColor(score.overallScore),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  score.part.japaneseName,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'ボリューム: ${score.volume.toStringAsFixed(1)} / ディフィニション: ${score.definition.toStringAsFixed(1)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.textTheme.bodySmall?.color?.withAlpha(150),
                                  ),
                                ),
                              ],
                            ),
                            if (comment != null && comment.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                comment,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.4,
                                  color: theme.textTheme.bodyMedium?.color?.withAlpha(220),
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 8),
                              const Text(
                                '分析コメントはありません',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!isLast) const Divider(height: 1, indent: 76),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _PartDetailsCard extends StatelessWidget {
  final MusclePartScore partScore;
  final bool isPro;

  const _PartDetailsCard({
    required this.partScore,
    required this.isPro,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Center(
                  child: Text(
                    partScore.overallScore.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.getScoreColor(partScore.overallScore),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        partScore.part.japaneseName,
                        style: theme.textTheme.titleLarge,
                      ),
                      Text(
                        partScore.part.englishName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withAlpha(150),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Score Breakdown
            _ScoreBar(label: 'ボリューム', value: partScore.volume, maxValue: 10),
            const SizedBox(height: 12),
            _ScoreBar(
                label: 'ディフィニション', value: partScore.definition, maxValue: 10),

            if (isPro) ...[
              const SizedBox(height: 12),
              _ScoreBar(
                label: '左右対称性',
                value: partScore.symmetry ?? 0,
                maxValue: 10,
              ),
              const SizedBox(height: 12),
              _ScoreBar(
                label: '脂肪の見た目',
                value: partScore.fatAppearance ?? 0,
                maxValue: 10,
                inverted: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  final String label;
  final double value;
  final double maxValue;
  final bool inverted;

  const _ScoreBar({
    required this.label,
    required this.value,
    required this.maxValue,
    this.inverted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayValue = inverted ? (maxValue - value) : value;
    final progress = (value / maxValue).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            Text(
              displayValue.toStringAsFixed(1),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: theme.colorScheme.onSurface.withAlpha(25),
          valueColor: AlwaysStoppedAnimation(
            AppTheme.getScoreColor(displayValue),
          ),
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
      ],
    );
  }
}
