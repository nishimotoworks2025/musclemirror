import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/muscle_data.dart';
import '../services/gemini_service.dart';
import '../theme/app_theme.dart';
import 'camera_capture_screen.dart';
import '../services/face_mosaic_service.dart';

class DiagnosisScreen extends StatefulWidget {
  final EvaluationType evaluationType;
  final bool isPro;

  const DiagnosisScreen({
    super.key,
    required this.evaluationType,
    required this.isPro,
  });

  @override
  State<DiagnosisScreen> createState() => _DiagnosisScreenState();
}

class _DiagnosisScreenState extends State<DiagnosisScreen>
    with SingleTickerProviderStateMixin {
  final _picker = ImagePicker();
  final _geminiService = GeminiService(); // Uses AppConfig automatically
  
  Uint8List? _imageBytes;
  
  bool _isAnalyzing = false;
  String _statusMessage = '';
  
  late AnimationController _animationController;
  
  PreCheckResult? _preCheckResult;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    if (source == ImageSource.camera) {
      await _openCamera();
      return;
    }
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        await _setImageFromFile(File(pickedFile.path), pickedFile.readAsBytes());
      }
    } catch (e) {
      _showError('画像の取得に失敗しました: $e');
    }
  }

  Future<void> _openCamera() async {
    try {
      final file = await Navigator.of(context).push<XFile>(
        MaterialPageRoute(
          builder: (_) => const CameraCaptureScreen(),
          fullscreenDialog: true,
        ),
      );
      if (file == null) return;
      await _setImageFromFile(File(file.path), file.readAsBytes());
    } catch (e) {
      _showError('画像の取得に失敗しました: $e');
    }
  }

  Future<void> _setImageFromFile(File file, Future<Uint8List> bytesFuture) async {
    final bytes = await bytesFuture;
    final normalizedBytes = await _normalizeImageBytes(bytes);
    if (!mounted) return;
    setState(() {
      _imageBytes = normalizedBytes;
      _preCheckResult = null;
      _statusMessage = '';
    });

    // Show preview confirmation dialog
    _showPreviewConfirmation();
  }

  /// Show preview confirmation dialog with face mosaic applied
  Future<void> _showPreviewConfirmation() async {
    if (_imageBytes == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '画像を確認',
                style: Theme.of(dialogContext).textTheme.titleLarge,
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(dialogContext).size.height * 0.5,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: MosaicImage(
                  imageBytes: _imageBytes!,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('やり直す'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('この画像で判定'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;

    if (confirmed == true) {
      _runPreCheck();
    } else {
      setState(() => _imageBytes = null);
    }
  }

  Future<Uint8List> _normalizeImageBytes(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    final oriented = img.bakeOrientation(decoded);
    const maxSide = 1024;
    final shouldResize =
        oriented.width > maxSide || oriented.height > maxSide;

    final resized = shouldResize
        ? img.copyResize(
            oriented,
            width: oriented.width >= oriented.height ? maxSide : null,
            height: oriented.height > oriented.width ? maxSide : null,
          )
        : oriented;

    return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
  }

  Future<void> _runPreCheck() async {
    if (_imageBytes == null) return;

    setState(() {
      _isAnalyzing = true;
      _statusMessage = '服装・構図を判定中...';
    });

    try {
      final result = await _geminiService.preCheck(_imageBytes!);
      
      if (!mounted) return;
      
      setState(() {
        _preCheckResult = result;
        _isAnalyzing = false;
      });

      if (result.level == PreCheckLevel.pass || result.level == PreCheckLevel.warn) {
        // Auto-start evaluation if PASS, or if WARN (Pro users or warning acknowledged)
        // For now, let's require manual start for WARN to show the warning
        if (result.level == PreCheckLevel.pass) {
           _runEvaluation();
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAnalyzing = false);
      _showError('判定中にエラーが発生しました');
    }
  }

  Future<void> _runEvaluation() async {
    if (_imageBytes == null) return;

    setState(() {
      _isAnalyzing = true;
      _statusMessage = '筋肉の状態を分析中...\n(10-20秒ほどかかります)';
    });

    try {
      // Save the image to app storage
      String? savedImagePath;
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final imagesDir = Directory('${appDir.path}/diagnosis_images');
        if (!await imagesDir.exists()) {
          await imagesDir.create(recursive: true);
        }
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final imageFile = File('${imagesDir.path}/diagnosis_$timestamp.jpg');
        await imageFile.writeAsBytes(_imageBytes!);
        savedImagePath = imageFile.path;
        debugPrint('Image saved to: $savedImagePath');
      } catch (e) {
        debugPrint('Failed to save image: $e');
      }

      final evaluation = await _geminiService.evaluate(
        imageBytes: _imageBytes!,
        evaluationType: widget.evaluationType,
        isPro: widget.isPro,
      );

      if (!mounted) return;
      
      // Navigate to results
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => 
              // Assuming you have a result screen like TrueSkin
              // ResultScreen(evaluation: evaluation)
              // Or you go back to overview and pass the result
              Scaffold(
                appBar: AppBar(title: const Text('判定完了')),
                body: const Center(child: Text('判定結果を表示する画面へ遷移します...')),
              ),
        ),
      );
      // Let's actually pop and return the evaluation to the caller (HomeScreen)
      Navigator.of(context).pop(evaluation);

    } catch (e) {
      if (!mounted) return;
      setState(() => _isAnalyzing = false);
      _showError('分析中にエラーが発生しました: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('筋肉判定'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Image Preview Area
          Expanded(
            child: Container(
              width: double.infinity,
              color: Colors.black,
              child: _imageBytes != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        // Base image with face mosaic
                        MosaicImage(
                          imageBytes: _imageBytes!,
                          fit: BoxFit.contain,
                        ),
                        // Analysis overlay
                        if (_isAnalyzing)
                          _buildAnalysisOverlay(theme),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.fitness_center, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text(
                          '自撮り写真をアップロード',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FilledButton.icon(
                              onPressed: () => _pickImage(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('カメラで撮影'),
                            ),
                            const SizedBox(width: 16),
                            OutlinedButton.icon(
                              onPressed: () => _pickImage(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library),
                              label: const Text('アルバムから'),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),

          // Analysis Status / Controls (only shown when not analyzing)
          if (!_isAnalyzing && _preCheckResult != null)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(25),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                child: _buildPreCheckResult(theme),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAnalysisOverlay(ThemeData theme) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final progress = _animationController.value;
        return Container(
          color: Colors.black.withOpacity(0.6),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Scanning line effect
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                bottom: 0,
                child: CustomPaint(
                  painter: _ScanLinePainter(progress: progress),
                ),
              ),
              // Center content
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Pulsing rings
                  SizedBox(
                    width: 150,
                    height: 150,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer pulsing ring
                        Transform.scale(
                          scale: 1.0 + (progress * 0.3),
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.brandBlue.withOpacity(1.0 - progress),
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                        // Middle ring
                        Transform.scale(
                          scale: 1.0 + ((progress + 0.33) % 1.0 * 0.3),
                          child: Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.brandBlue.withOpacity(1.0 - (progress + 0.33) % 1.0),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        // Inner rotating indicator
                        Transform.rotate(
                          angle: progress * 6.28,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: SweepGradient(
                                colors: [
                                  AppTheme.brandBlue.withOpacity(0.0),
                                  AppTheme.brandBlue.withOpacity(0.8),
                                  AppTheme.brandBlue.withOpacity(0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Center icon
                        Icon(
                          Icons.fitness_center,
                          color: Colors.white,
                          size: 32,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Status message
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Animated dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (index) {
                      final delayedProgress = (progress + index * 0.2) % 1.0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Opacity(
                          opacity: 0.3 + (delayedProgress > 0.5 ? 1.0 - delayedProgress : delayedProgress) * 1.4,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppTheme.brandBlue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPreCheckResult(ThemeData theme) {
    if (_preCheckResult!.level == PreCheckLevel.pass && !_isAnalyzing) {
      // Should have moved to evaluation automatically, but if stuck:
       return const SizedBox.shrink(); // Wait for evaluation to finish or just show loading if manual
    }
    
    // WARN or FAIL
    final isWarn = _preCheckResult!.level == PreCheckLevel.warn;
    final color = isWarn ? AppTheme.accentOrange : AppTheme.accentRed;
    final icon = isWarn ? Icons.warning_amber : Icons.error_outline;
    final title = isWarn ? '画像判定: 注意' : '画像判定: エラー';
    final reason = preCheckReasonMessages[_preCheckResult!.reasonCode] ?? '不明な理由により判定できませんでした';
    
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                 color: color,
                 fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(reason, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 24),
        
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pickImage(ImageSource.camera),
                child: const Text('再撮影'),
              ),
            ),
            if (isWarn) ...[
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: _runEvaluation,
                  child: const Text('このまま判定する'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// Custom painter for scanning line effect
class _ScanLinePainter extends CustomPainter {
  final double progress;

  const _ScanLinePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          AppTheme.brandBlue.withOpacity(0.5),
          AppTheme.brandBlue.withOpacity(0.8),
          AppTheme.brandBlue.withOpacity(0.5),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 40));

    // Scan line position (moves up and down)
    final double scanY = progress < 0.5
        ? progress * 2.0 * size.height
        : (1.0 - (progress - 0.5) * 2.0) * size.height;

    canvas.drawRect(
      Rect.fromLTWH(0, scanY - 20, size.width, 40),
      paint,
    );

    // Grid lines for tech effect
    final gridPaint = Paint()
      ..color = AppTheme.brandBlue.withOpacity(0.1)
      ..strokeWidth = 1;

    // Horizontal grid lines
    for (var y = 0.0; y < size.height; y += 30) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    // Vertical grid lines
    for (var x = 0.0; x < size.width; x += 30) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScanLinePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
