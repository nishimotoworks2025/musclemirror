import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Service for detecting faces and applying mosaic effect
class FaceMosaicService {
  static final FaceMosaicService _instance = FaceMosaicService._internal();
  factory FaceMosaicService() => _instance;
  FaceMosaicService._internal();

  FaceDetector? _faceDetector;

  FaceDetector get faceDetector {
    _faceDetector ??= FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableContours: false,
        enableLandmarks: false,
        enableClassification: false,
        enableTracking: false,
      ),
    );
    return _faceDetector!;
  }

  /// Close the face detector when not needed
  Future<void> dispose() async {
    await _faceDetector?.close();
    _faceDetector = null;
  }

  /// Apply mosaic effect to faces in the image
  /// Returns the processed image bytes with faces pixelated
  Future<Uint8List> applyFaceMosaic(Uint8List imageBytes) async {
    File? tempFile;
    try {
      // Decode the image
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return imageBytes;

      // Apply orientation fix
      final oriented = img.bakeOrientation(decoded);

      // Save to temporary file for ML Kit
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      tempFile = File('${tempDir.path}/temp_face_detect_$timestamp.jpg');
      await tempFile.writeAsBytes(imageBytes);

      // Create InputImage from file path
      final inputImage = InputImage.fromFilePath(tempFile.path);

      // Detect faces
      final faces = await faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        debugPrint('No faces detected');
        return imageBytes;
      }

      debugPrint('Detected ${faces.length} face(s)');

      // Apply mosaic to each face
      var processedImage = oriented;
      for (final face in faces) {
        final boundingBox = face.boundingBox;
        
        // Expand the bounding box slightly for better coverage
        final expandedRect = _expandRect(
          boundingBox,
          oriented.width.toDouble(),
          oriented.height.toDouble(),
          expandRatio: 0.2,
        );

        // Apply pixelation to the face region
        processedImage = _applyPixelation(
          processedImage,
          expandedRect.left.toInt(),
          expandedRect.top.toInt(),
          expandedRect.width.toInt(),
          expandedRect.height.toInt(),
          pixelSize: 15,
        );
      }

      // Encode back to JPEG
      return Uint8List.fromList(img.encodeJpg(processedImage, quality: 85));
    } catch (e) {
      debugPrint('Error applying face mosaic: $e');
      return imageBytes;
    } finally {
      // Clean up temp file
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  /// Expand a rectangle by a ratio while keeping it within bounds
  Rect _expandRect(Rect rect, double maxWidth, double maxHeight, {double expandRatio = 0.2}) {
    final expandX = rect.width * expandRatio;
    final expandY = rect.height * expandRatio;

    return Rect.fromLTRB(
      (rect.left - expandX).clamp(0, maxWidth),
      (rect.top - expandY).clamp(0, maxHeight),
      (rect.right + expandX).clamp(0, maxWidth),
      (rect.bottom + expandY).clamp(0, maxHeight),
    );
  }

  /// Apply pixelation effect to a region of the image
  img.Image _applyPixelation(
    img.Image image,
    int x,
    int y,
    int width,
    int height, {
    int pixelSize = 10,
  }) {
    // Clamp values to image bounds
    final startX = x.clamp(0, image.width - 1);
    final startY = y.clamp(0, image.height - 1);
    final endX = (x + width).clamp(0, image.width);
    final endY = (y + height).clamp(0, image.height);

    // Process in blocks
    for (var py = startY; py < endY; py += pixelSize) {
      for (var px = startX; px < endX; px += pixelSize) {
        // Calculate block bounds
        final blockEndX = (px + pixelSize).clamp(0, endX);
        final blockEndY = (py + pixelSize).clamp(0, endY);

        // Get average color of the block
        int totalR = 0, totalG = 0, totalB = 0;
        int count = 0;

        for (var by = py; by < blockEndY; by++) {
          for (var bx = px; bx < blockEndX; bx++) {
            final pixel = image.getPixel(bx, by);
            totalR += pixel.r.toInt();
            totalG += pixel.g.toInt();
            totalB += pixel.b.toInt();
            count++;
          }
        }

        if (count > 0) {
          final avgR = totalR ~/ count;
          final avgG = totalG ~/ count;
          final avgB = totalB ~/ count;

          // Fill the block with average color
          for (var by = py; by < blockEndY; by++) {
            for (var bx = px; bx < blockEndX; bx++) {
              image.setPixelRgb(bx, by, avgR, avgG, avgB);
            }
          }
        }
      }
    }

    return image;
  }
}

/// Widget that displays an image with face mosaic applied
class MosaicImage extends StatefulWidget {
  final Uint8List imageBytes;
  final BoxFit fit;

  const MosaicImage({
    super.key,
    required this.imageBytes,
    this.fit = BoxFit.contain,
  });

  @override
  State<MosaicImage> createState() => _MosaicImageState();
}

class _MosaicImageState extends State<MosaicImage> {
  Uint8List? _processedBytes;
  bool _isProcessing = true;

  @override
  void initState() {
    super.initState();
    _processImage();
  }

  @override
  void didUpdateWidget(MosaicImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageBytes != widget.imageBytes) {
      _processImage();
    }
  }

  Future<void> _processImage() async {
    setState(() => _isProcessing = true);
    
    try {
      final service = FaceMosaicService();
      final processed = await service.applyFaceMosaic(widget.imageBytes);
      if (mounted) {
        setState(() {
          _processedBytes = processed;
          _isProcessing = false;
        });
      }
    } catch (e) {
      debugPrint('Error processing mosaic: $e');
      if (mounted) {
        setState(() {
          _processedBytes = widget.imageBytes;
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isProcessing) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Show blurred original while processing
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Image.memory(widget.imageBytes, fit: widget.fit),
          ),
          const Center(
            child: CircularProgressIndicator(),
          ),
        ],
      );
    }

    return Image.memory(
      _processedBytes ?? widget.imageBytes,
      fit: widget.fit,
    );
  }
}
