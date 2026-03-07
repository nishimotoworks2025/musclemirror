import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../widgets/body_highlight_painter.dart';

class BodyHighlightScreen extends StatefulWidget {
  const BodyHighlightScreen({super.key});

  @override
  State<BodyHighlightScreen> createState() => _BodyHighlightScreenState();
}

class _BodyHighlightScreenState extends State<BodyHighlightScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  late final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.single,
      model: PoseDetectionModel.accurate,
    ),
  );

  XFile? _imageFile;
  Size? _imageSize;
  Pose? _pose;
  BodyPart? _selectedPart;
  String? _errorMessage;
  bool _isProcessing = false;

  @override
  void dispose() {
    _poseDetector.close();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() {
      _imageFile = picked;
      _pose = null;
      _selectedPart = null;
      _errorMessage = null;
      _isProcessing = true;
    });

    try {
      final bytes = await File(picked.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final decoded = frame.image;
      final inputImage = InputImage.fromFilePath(picked.path);
      final poses = await _poseDetector.processImage(inputImage);
      final pose = poses.isNotEmpty ? poses.first : null;

      if (!mounted) return;

      if (pose == null || !BodyHighlightPainter.hasAnyDrawableParts(pose)) {
        setState(() {
          _imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
          _pose = pose;
          _errorMessage = 'Pose not detected. Try a clearer full-body photo.';
          _isProcessing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pose not detected. Try a clearer full-body photo.'),
          ),
        );
        return;
      }

      setState(() {
        _imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
        _pose = pose;
        _errorMessage = null;
        _isProcessing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Pose not detected. Try a clearer full-body photo.';
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pose not detected. Try a clearer full-body photo.'),
        ),
      );
    }
  }

  void _handleTap(Offset tapPosition, Size viewSize) {
    final pose = _pose;
    final imageSize = _imageSize;
    if (pose == null || imageSize == null) return;

    final parts = BodyHighlightPainter.buildPartPaths(
      pose: pose,
      imageSize: imageSize,
      viewSize: viewSize,
    );

    BodyPart? nextSelected;
    for (final part in BodyHighlightPainter.drawOrder) {
      final path = parts[part];
      if (path != null && path.contains(tapPosition)) {
        nextSelected = part;
        break;
      }
    }

    setState(() {
      _selectedPart = nextSelected;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Body Highlight'),
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _pickImage,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(_isProcessing ? 'Processing...' : 'Select Image'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: _imageFile == null || _imageSize == null
                  ? Text(
                      'Select a full-body image from your gallery.',
                      style: theme.textTheme.bodyMedium,
                    )
                  : AspectRatio(
                      aspectRatio: _imageSize!.width / _imageSize!.height,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final viewSize = Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );

                          return GestureDetector(
                            onTapDown: (details) => _handleTap(
                              details.localPosition,
                              viewSize,
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(
                                  File(_imageFile!.path),
                                  fit: BoxFit.contain,
                                ),
                                CustomPaint(
                                  painter: BodyHighlightPainter(
                                    pose: _pose,
                                    imageSize: _imageSize,
                                    selectedPart: _selectedPart,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _errorMessage!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Text(
              _selectedPart == null
                  ? 'Selected: None'
                  : 'Selected: ${bodyPartLabel(_selectedPart!)}',
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}
