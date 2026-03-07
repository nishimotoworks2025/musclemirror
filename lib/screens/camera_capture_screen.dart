import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  bool _isInitializing = true;
  bool _isCapturing = false;
  int _timerSeconds = 0;
  int? _countdown;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final selected = _selectDefaultCamera(cameras);
      final controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted) return;
      setState(() {
        _cameras = cameras;
        _controller = controller;
        _isInitializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
      });
      _showError('Failed to initialize camera: $e');
    }
  }

  CameraDescription _selectDefaultCamera(List<CameraDescription> cameras) {
    if (cameras.isEmpty) {
      throw StateError('No cameras available');
    }
    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.front) {
        return camera;
      }
    }
    return cameras.first;
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _controller == null) return;
    final current = _controller!.description;
    final nextIndex = (_cameras.indexOf(current) + 1) % _cameras.length;
    final next = _cameras[nextIndex];
    await _controller!.dispose();
    final controller = CameraController(
      next,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await controller.initialize();
    if (!mounted) return;
    setState(() {
      _controller = controller;
    });
  }

  void _startCapture() {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) {
      return;
    }
    if (_timerSeconds > 0) {
      _beginCountdown();
    } else {
      _captureNow();
    }
  }

  void _beginCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _countdown = _timerSeconds;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final next = (_countdown ?? 0) - 1;
      if (next <= 0) {
        timer.cancel();
        setState(() {
          _countdown = null;
        });
        _captureNow();
      } else {
        setState(() {
          _countdown = next;
        });
      }
    });
  }

  Future<void> _captureNow() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() {
      _isCapturing = true;
    });
    try {
      final file = await _controller!.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(file);
    } catch (e) {
      _showError('Failed to take picture: $e');
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
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
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Camera'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _switchCamera,
            icon: const Icon(Icons.cameraswitch),
            tooltip: 'Switch camera',
          ),
        ],
      ),
      body: _isInitializing || controller == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Center(
                  child: _buildCameraPreview(context, controller),
                ),
                const IgnorePointer(
                  child: CustomPaint(
                    painter: _BodyGuidePainter(),
                    child: SizedBox.expand(),
                  ),
                ),
                if (_countdown != null)
                  Center(
                    child: Text(
                      '$_countdown',
                      style: theme.textTheme.displayLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(140),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _TimerSelector(
                            value: _timerSeconds,
                            onChanged: (value) => setState(() {
                              _timerSeconds = value;
                            }),
                          ),
                          FloatingActionButton(
                            onPressed: _isCapturing ? null : _startCapture,
                            backgroundColor: theme.colorScheme.primary,
                            child: _isCapturing
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : const Icon(Icons.camera_alt),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

Widget _buildCameraPreview(BuildContext context, CameraController controller) {
  final size = MediaQuery.of(context).size;
  final isPortrait = size.height >= size.width;
  final previewRatio = controller.value.aspectRatio;
  final effectiveRatio = isPortrait ? 1 / previewRatio : previewRatio;
  final screenRatio = size.width / size.height;

  final double previewWidth;
  final double previewHeight;
  if (effectiveRatio > screenRatio) {
    previewHeight = size.height;
    previewWidth = size.height * effectiveRatio;
  } else {
    previewWidth = size.width;
    previewHeight = size.width / effectiveRatio;
  }

  return ClipRect(
    child: OverflowBox(
      alignment: Alignment.center,
      child: SizedBox(
        width: previewWidth,
        height: previewHeight,
        child: CameraPreview(controller),
      ),
    ),
  );
}

class _TimerSelector extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _TimerSelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final label = value == 0 ? 'Timer: Off' : 'Timer: ${value}s';
    return PopupMenuButton<int>(
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(value: 0, child: Text('Off')),
        PopupMenuItem(value: 3, child: Text('3s')),
        PopupMenuItem(value: 5, child: Text('5s')),
        PopupMenuItem(value: 10, child: Text('10s')),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _BodyGuidePainter extends CustomPainter {
  const _BodyGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final scale = size.width / 400;

    // Body dimensions - simplified minimalist pose
    final h = size.height * 0.72;        // total body height
    final top = size.height * 0.10;      // top margin

    final headRadius = h * 0.06;
    final headCenterY = top + headRadius;
    
    // Y positions
    final shoulderY = top + h * 0.18;
    final hipY = top + h * 0.52;
    final handY = top + h * 0.54;
    final ankleY = top + h * 0.95;

    // X widths
    final shoulderW = h * 0.14;
    final handW = h * 0.18;
    final hipW = h * 0.09;
    final ankleW = h * 0.05;

    final strokePaint = Paint()
      ..color = Colors.white.withAlpha(120)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final p = Path();

    // Head (Circle)
    p.addOval(Rect.fromCircle(center: Offset(cx, headCenterY), radius: headRadius));

    // Spine (Neck to Hips)
    p.moveTo(cx, headCenterY + headRadius);
    p.lineTo(cx, hipY);

    // Shoulders (Straight line)
    p.moveTo(cx - shoulderW, shoulderY);
    p.lineTo(cx + shoulderW, shoulderY);

    // Hips (Straight line)
    p.moveTo(cx - hipW, hipY);
    p.lineTo(cx + hipW, hipY);

    // Right Arm (Simple line from shoulder to hand)
    p.moveTo(cx + shoulderW, shoulderY);
    p.lineTo(cx + handW, handY);

    // Left Arm (Simple line from shoulder to hand)
    p.moveTo(cx - shoulderW, shoulderY);
    p.lineTo(cx - handW, handY);

    // Right Leg (Simple line from hip to ankle)
    p.moveTo(cx + hipW, hipY);
    p.lineTo(cx + ankleW, ankleY);

    // Left Leg (Simple line from hip to ankle)
    p.moveTo(cx - hipW, hipY);
    p.lineTo(cx - ankleW, ankleY);

    canvas.drawPath(p, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
