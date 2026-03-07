import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

enum BodyPart {
  chest,
  leftUpperArm,
  rightUpperArm,
  leftForearm,
  rightForearm,
}

String bodyPartLabel(BodyPart part) {
  switch (part) {
    case BodyPart.chest:
      return 'Chest';
    case BodyPart.leftUpperArm:
      return 'Left Upper Arm';
    case BodyPart.rightUpperArm:
      return 'Right Upper Arm';
    case BodyPart.leftForearm:
      return 'Left Forearm';
    case BodyPart.rightForearm:
      return 'Right Forearm';
  }
}

class BodyHighlightPainter extends CustomPainter {
  final Pose? pose;
  final Size? imageSize;
  final BodyPart? selectedPart;

  BodyHighlightPainter({
    required this.pose,
    required this.imageSize,
    required this.selectedPart,
  });

  static const List<BodyPart> drawOrder = [
    BodyPart.chest,
    BodyPart.leftUpperArm,
    BodyPart.rightUpperArm,
    BodyPart.leftForearm,
    BodyPart.rightForearm,
  ];

  static const Map<BodyPart, Color> partColors = {
    BodyPart.chest: Colors.orange,
    BodyPart.leftUpperArm: Colors.blue,
    BodyPart.rightUpperArm: Colors.green,
    BodyPart.leftForearm: Colors.teal,
    BodyPart.rightForearm: Colors.pink,
  };

  static bool hasAnyDrawableParts(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    if (leftShoulder == null || rightShoulder == null) {
      return false;
    }

    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
    final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];
    final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];

    final hasChest = leftHip != null && rightHip != null;
    final hasLeftUpperArm = leftElbow != null;
    final hasRightUpperArm = rightElbow != null;
    final hasLeftForearm = leftElbow != null && leftWrist != null;
    final hasRightForearm = rightElbow != null && rightWrist != null;

    return hasChest || hasLeftUpperArm || hasRightUpperArm || hasLeftForearm || hasRightForearm;
  }

  static Map<BodyPart, Path> buildPartPaths({
    required Pose pose,
    required Size imageSize,
    required Size viewSize,
  }) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];

    if (leftShoulder == null || rightShoulder == null) {
      return {};
    }

    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
    final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];
    final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];

    final scale = min(
      viewSize.width / imageSize.width,
      viewSize.height / imageSize.height,
    );
    final dx = (viewSize.width - imageSize.width * scale) / 2;
    final dy = (viewSize.height - imageSize.height * scale) / 2;

    Offset mapPoint(Offset p) => Offset(dx + p.dx * scale, dy + p.dy * scale);

    Offset? toOffset(PoseLandmark? landmark) {
      if (landmark == null) return null;
      return Offset(landmark.x, landmark.y);
    }

    final leftShoulderPt = toOffset(leftShoulder);
    final rightShoulderPt = toOffset(rightShoulder);
    if (leftShoulderPt == null || rightShoulderPt == null) {
      return {};
    }

    final shoulderDist = (leftShoulderPt - rightShoulderPt).distance;
    if (shoulderDist == 0) {
      return {};
    }

    final upperArmWidth = 0.12 * shoulderDist;
    final forearmWidth = 0.10 * shoulderDist;

    final parts = <BodyPart, Path>{};

    if (leftHip != null && rightHip != null) {
      final leftHipPt = toOffset(leftHip);
      final rightHipPt = toOffset(rightHip);
      if (leftHipPt != null && rightHipPt != null) {
        final leftHipAdjusted = leftShoulderPt + (leftHipPt - leftShoulderPt) * 0.55;
        final rightHipAdjusted = rightShoulderPt + (rightHipPt - rightShoulderPt) * 0.55;

        final chestPath = Path()
          ..addPolygon(
            [
              mapPoint(leftShoulderPt),
              mapPoint(rightShoulderPt),
              mapPoint(rightHipAdjusted),
              mapPoint(leftHipAdjusted),
            ],
            true,
          );
        parts[BodyPart.chest] = chestPath;
      }
    }

    Path? buildBand(Offset p0, Offset p1, double width) {
      final dx = p1.dx - p0.dx;
      final dy = p1.dy - p0.dy;
      final length = sqrt(dx * dx + dy * dy);
      if (length == 0) return null;
      final nx = -dy / length;
      final ny = dx / length;
      final halfWidth = width / 2;
      final offset = Offset(nx * halfWidth, ny * halfWidth);

      final points = [
        mapPoint(p0 + offset),
        mapPoint(p1 + offset),
        mapPoint(p1 - offset),
        mapPoint(p0 - offset),
      ];

      return Path()..addPolygon(points, true);
    }

    if (leftElbow != null) {
      final leftElbowPt = toOffset(leftElbow);
      if (leftElbowPt != null) {
        final upperLeft = buildBand(leftShoulderPt, leftElbowPt, upperArmWidth);
        if (upperLeft != null) {
          parts[BodyPart.leftUpperArm] = upperLeft;
        }
      }
    }

    if (rightElbow != null) {
      final rightElbowPt = toOffset(rightElbow);
      if (rightElbowPt != null) {
        final upperRight = buildBand(rightShoulderPt, rightElbowPt, upperArmWidth);
        if (upperRight != null) {
          parts[BodyPart.rightUpperArm] = upperRight;
        }
      }
    }

    if (leftElbow != null && leftWrist != null) {
      final leftElbowPt = toOffset(leftElbow);
      final leftWristPt = toOffset(leftWrist);
      if (leftElbowPt != null && leftWristPt != null) {
        final foreLeft = buildBand(leftElbowPt, leftWristPt, forearmWidth);
        if (foreLeft != null) {
          parts[BodyPart.leftForearm] = foreLeft;
        }
      }
    }

    if (rightElbow != null && rightWrist != null) {
      final rightElbowPt = toOffset(rightElbow);
      final rightWristPt = toOffset(rightWrist);
      if (rightElbowPt != null && rightWristPt != null) {
        final foreRight = buildBand(rightElbowPt, rightWristPt, forearmWidth);
        if (foreRight != null) {
          parts[BodyPart.rightForearm] = foreRight;
        }
      }
    }

    return parts;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (pose == null || imageSize == null) {
      return;
    }

    final parts = buildPartPaths(
      pose: pose!,
      imageSize: imageSize!,
      viewSize: size,
    );

    for (final part in drawOrder) {
      final path = parts[part];
      if (path == null) continue;
      final isSelected = part == selectedPart;
      final baseColor = partColors[part] ?? Colors.grey;
      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = baseColor.withOpacity(isSelected ? 0.45 : 0.25);
      canvas.drawPath(path, fillPaint);

      if (isSelected) {
        final strokePaint = Paint()
          ..style = PaintingStyle.stroke
          ..color = baseColor.withOpacity(0.9)
          ..strokeWidth = 2;
        canvas.drawPath(path, strokePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant BodyHighlightPainter oldDelegate) {
    return oldDelegate.pose != pose ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.selectedPart != selectedPart;
  }
}
