/// Pose detection service for body part highlighting.
/// 
/// This service uses Google ML Kit Pose Detection to extract body landmarks
/// and generates polygons for each muscle part based on the detected pose.
library;

import 'dart:math' as math;
import 'dart:ui';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../models/muscle_data.dart';

// =========================
// Geometry helpers
// =========================

/// Calculate distance between two points.
double dist(Offset a, Offset b) {
  return (a - b).distance;
}

/// Linear interpolation between two points.
Offset lerp(Offset a, Offset b, double t) {
  return Offset(
    a.dx + (b.dx - a.dx) * t,
    a.dy + (b.dy - a.dy) * t,
  );
}

/// Create a thick segment polygon (4 points) around p0->p1 with width w.
List<Offset> bandPolygon(Offset p0, Offset p1, double w) {
  final v = p1 - p0;
  final length = v.distance;
  if (length < 1e-6) return [];
  
  // Unit normal vector
  final n = Offset(-v.dy / length, v.dx / length);
  final half = w / 2.0;
  
  return [
    p0 + n * half,
    p1 + n * half,
    p1 - n * half,
    p0 - n * half,
  ];
}

/// Create a circle polygon with n points.
List<Offset> circlePolygon(Offset center, double r, {int n = 20}) {
  final points = <Offset>[];
  for (int i = 0; i < n; i++) {
    final theta = 2 * math.pi * i / n;
    points.add(Offset(
      center.dx + r * math.cos(theta),
      center.dy + r * math.sin(theta),
    ));
  }
  return points;
}

// =========================
// Landmarks data class
// =========================

/// Container for extracted pose landmarks in pixel coordinates.
class PoseLandmarks {
  final Map<String, Offset> points;
  
  const PoseLandmarks({required this.points});
  
  bool has(List<String> keys) {
    return keys.every((k) => points.containsKey(k) && points[k] != null);
  }
  
  Offset? operator [](String key) => points[key];
}

// =========================
// Body part polygons
// =========================

/// Generated body part polygons from pose landmarks.
class BodyPartPolygons {
  final Map<String, List<Offset>> parts;
  
  const BodyPartPolygons({required this.parts});
  
  /// Get polygons for a MusclePart (returns separate lists for left/right to avoid drawing lines across the body).
  List<List<Offset>>? getPolygonsForPart(MusclePart part) {
    final result = <List<Offset>>[];
    void addIfPresent(String key) {
      if (parts[key] != null && parts[key]!.isNotEmpty) {
        result.add(parts[key]!);
      }
    }

    switch (part) {
      case MusclePart.shoulder:
        addIfPresent('肩(左)');
        addIfPresent('肩(右)');
        break;
      case MusclePart.chest:
        addIfPresent('胸');
        break;
      case MusclePart.arm:
        addIfPresent('腕(左)');
        addIfPresent('腕(右)');
        break;
      case MusclePart.forearm:
        addIfPresent('前腕(左)');
        addIfPresent('前腕(右)');
        break;
      case MusclePart.abs:
        addIfPresent('腹');
        break;
      case MusclePart.leg:
        addIfPresent('脚(左)');
        addIfPresent('脚(右)');
        break;
      case MusclePart.calf:
        addIfPresent('ふくらはぎ(左)');
        addIfPresent('ふくらはぎ(右)');
        break;
      case MusclePart.back:
        addIfPresent('背中(参考)');
        break;
    }
    return result.isEmpty ? null : result;
  }
}

/// Build body part polygons from landmarks (ported from Python).
BodyPartPolygons buildParts(PoseLandmarks lm) {
  final parts = <String, List<Offset>>{};
  
  double shoulderDist = 0.0;
  if (lm.has(['L_SHOULDER', 'R_SHOULDER'])) {
    shoulderDist = dist(lm['L_SHOULDER']!, lm['R_SHOULDER']!);
  }
  
  double hipDist = 0.0;
  if (lm.has(['L_HIP', 'R_HIP'])) {
    hipDist = dist(lm['L_HIP']!, lm['R_HIP']!);
  } else {
    hipDist = shoulderDist > 0 ? shoulderDist * 0.9 : 150.0;
  }
  
  // Shoulders (small circles)
  if (shoulderDist > 0) {
    final r = 0.18 * shoulderDist;
    if (lm.has(['L_SHOULDER'])) {
      parts['肩(左)'] = circlePolygon(lm['L_SHOULDER']!, r, n: 24);
    }
    if (lm.has(['R_SHOULDER'])) {
      parts['肩(右)'] = circlePolygon(lm['R_SHOULDER']!, r, n: 24);
    }
  }
  
  // Chest & Abs
  if (lm.has(['L_SHOULDER', 'R_SHOULDER', 'L_HIP', 'R_HIP'])) {
    final lShoulder = lm['L_SHOULDER']!;
    final rShoulder = lm['R_SHOULDER']!;
    final lHip = lm['L_HIP']!;
    final rHip = lm['R_HIP']!;
    
    // Chest: from shoulders to about 55% toward hips
    final lChestBottom = lerp(lShoulder, lHip, 0.55);
    final rChestBottom = lerp(rShoulder, rHip, 0.55);
    parts['胸'] = [lShoulder, rShoulder, rChestBottom, lChestBottom];
    
    // Abs: from 55% to 90% toward hips
    final lAbsBottom = lerp(lShoulder, lHip, 0.90);
    final rAbsBottom = lerp(rShoulder, rHip, 0.90);
    parts['腹'] = [lChestBottom, rChestBottom, rAbsBottom, lAbsBottom];
  }
  
  // Arms (upper arm: shoulder to elbow)
  if (shoulderDist > 0) {
    final upperW = 0.20 * shoulderDist;
    final foreW = 0.16 * shoulderDist;
    
    if (lm.has(['L_SHOULDER', 'L_ELBOW'])) {
      parts['腕(左)'] = bandPolygon(lm['L_SHOULDER']!, lm['L_ELBOW']!, upperW);
    }
    if (lm.has(['R_SHOULDER', 'R_ELBOW'])) {
      parts['腕(右)'] = bandPolygon(lm['R_SHOULDER']!, lm['R_ELBOW']!, upperW);
    }
    
    // Forearms (elbow to wrist)
    if (lm.has(['L_ELBOW', 'L_WRIST'])) {
      parts['前腕(左)'] = bandPolygon(lm['L_ELBOW']!, lm['L_WRIST']!, foreW);
    }
    if (lm.has(['R_ELBOW', 'R_WRIST'])) {
      parts['前腕(右)'] = bandPolygon(lm['R_ELBOW']!, lm['R_WRIST']!, foreW);
    }
  }
  
  // Legs (hip to knee)
  final thighW = 0.24 * hipDist;
  final calfW = 0.18 * hipDist;
  
  if (lm.has(['L_HIP', 'L_KNEE'])) {
    parts['脚(左)'] = bandPolygon(lm['L_HIP']!, lm['L_KNEE']!, thighW);
  }
  if (lm.has(['R_HIP', 'R_KNEE'])) {
    parts['脚(右)'] = bandPolygon(lm['R_HIP']!, lm['R_KNEE']!, thighW);
  }
  
  // Calves (knee to ankle)
  if (lm.has(['L_KNEE', 'L_ANKLE'])) {
    parts['ふくらはぎ(左)'] = bandPolygon(lm['L_KNEE']!, lm['L_ANKLE']!, calfW);
  }
  if (lm.has(['R_KNEE', 'R_ANKLE'])) {
    parts['ふくらはぎ(右)'] = bandPolygon(lm['R_KNEE']!, lm['R_ANKLE']!, calfW);
  }
  
  // Back (cannot be observed from front photo)
  parts['背中(参考)'] = [];
  
  return BodyPartPolygons(parts: parts);
}

// =========================
// Pose detection service
// =========================

class PoseService {
  static final PoseService _instance = PoseService._internal();
  factory PoseService() => _instance;
  PoseService._internal();
  
  PoseDetector? _poseDetector;
  
  PoseDetector get _detector {
    _poseDetector ??= PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.single,
        model: PoseDetectionModel.accurate,
      ),
    );
    return _poseDetector!;
  }
  
  /// Extract landmarks from an image file.
  Future<PoseLandmarks?> extractLandmarks(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    
    try {
      final poses = await _detector.processImage(inputImage);
      
      if (poses.isEmpty) {
        return null;
      }
      
      final pose = poses.first;
      final landmarks = pose.landmarks;
      
      final points = <String, Offset>{};
      
      // Map ML Kit landmark types to our naming convention
      final landmarkMap = {
        'L_SHOULDER': PoseLandmarkType.leftShoulder,
        'R_SHOULDER': PoseLandmarkType.rightShoulder,
        'L_ELBOW': PoseLandmarkType.leftElbow,
        'R_ELBOW': PoseLandmarkType.rightElbow,
        'L_WRIST': PoseLandmarkType.leftWrist,
        'R_WRIST': PoseLandmarkType.rightWrist,
        'L_HIP': PoseLandmarkType.leftHip,
        'R_HIP': PoseLandmarkType.rightHip,
        'L_KNEE': PoseLandmarkType.leftKnee,
        'R_KNEE': PoseLandmarkType.rightKnee,
        'L_ANKLE': PoseLandmarkType.leftAnkle,
        'R_ANKLE': PoseLandmarkType.rightAnkle,
      };
      
      for (final entry in landmarkMap.entries) {
        final landmark = landmarks[entry.value];
        if (landmark != null) {
          points[entry.key] = Offset(landmark.x, landmark.y);
        }
      }
      
      return PoseLandmarks(points: points);
    } catch (e) {
      print('Pose detection error: $e');
      return null;
    }
  }
  
  /// Extract landmarks and build body part polygons.
  Future<BodyPartPolygons?> detectBodyParts(String imagePath) async {
    final landmarks = await extractLandmarks(imagePath);
    if (landmarks == null) {
      return null;
    }
    return buildParts(landmarks);
  }
  
  /// Close the detector when done.
  Future<void> dispose() async {
    await _poseDetector?.close();
    _poseDetector = null;
  }
}
