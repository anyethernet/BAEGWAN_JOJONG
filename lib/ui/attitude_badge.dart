import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../control/attitude.dart';

/// Small 3D vehicle that follows roll / pitch / yaw, for the top-right corner.
class AttitudeBadge extends StatefulWidget {
  const AttitudeBadge({
    super.key,
    required this.attitude,
    this.width = 132,
    this.height = 118,
  });

  final Attitude attitude;
  final double width;
  final double height;

  @override
  State<AttitudeBadge> createState() => _AttitudeBadgeState();
}

class _AttitudeBadgeState extends State<AttitudeBadge>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _roll = 0;
  double _pitch = 0;
  double _yaw = 0;

  @override
  void initState() {
    super.initState();
    _roll = widget.attitude.roll;
    _pitch = widget.attitude.pitch;
    _yaw = widget.attitude.yaw;
    _ticker = createTicker((_) {
      final t = widget.attitude;
      final nextRoll = _roll + (t.roll - _roll) * 0.18;
      final nextPitch = _pitch + (t.pitch - _pitch) * 0.18;
      final nextYaw = _yaw + (t.yaw - _yaw) * 0.18;
      if ((nextRoll - _roll).abs() < 0.01 &&
          (nextPitch - _pitch).abs() < 0.01 &&
          (nextYaw - _yaw).abs() < 0.01) {
        return;
      }
      setState(() {
        _roll = nextRoll;
        _pitch = nextPitch;
        _yaw = nextYaw;
      });
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xB30B1630),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xAA8FB4FF)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: widget.width - 12,
                height: widget.height - 36,
                child: CustomPaint(
                  painter: _AttitudePainter(
                    roll: _roll,
                    pitch: _pitch,
                    yaw: _yaw,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'R ${_roll.toStringAsFixed(0)}  P ${_pitch.toStringAsFixed(0)}  Y ${_yaw.toStringAsFixed(0)}',
                maxLines: 1,
                style: const TextStyle(
                  color: Color(0xFFF3F7FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Vec {
  const _Vec(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

class _Face {
  const _Face(this.pts, this.color);
  final List<_Vec> pts;
  final Color color;
}

class _AttitudePainter extends CustomPainter {
  const _AttitudePainter({
    required this.roll,
    required this.pitch,
    required this.yaw,
  });

  final double roll;
  final double pitch;
  final double yaw;

  static const _faces = <_Face>[
    _Face([
      _Vec(0, 32, -3),
      _Vec(18, 0, -2),
      _Vec(0, -18, -2),
      _Vec(-18, 0, -2),
    ], Color(0xFF6E5310)),
    _Face([
      _Vec(-3, -16, 1),
      _Vec(3, -16, 1),
      _Vec(2, -38, 0),
      _Vec(-2, -38, 0),
    ], Color(0xFFE6C229)),
    _Face([
      _Vec(-6, -6, 2),
      _Vec(-26, -14, 1),
      _Vec(-8, -20, 1),
    ], Color(0xFFD4AF37)),
    _Face([
      _Vec(6, -6, 2),
      _Vec(26, -14, 1),
      _Vec(8, -20, 1),
    ], Color(0xFFD4AF37)),
    _Face([
      _Vec(0, 32, 5),
      _Vec(18, 0, 4),
      _Vec(0, -18, 4),
      _Vec(-18, 0, 4),
    ], Color(0xFFF6DE7A)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)));
    _paintHorizon(canvas, size);
    _paintVehicle(canvas, size);
    canvas.restore();
  }

  void _paintHorizon(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-roll * math.pi / 180);
    final shift = (pitch.clamp(-35, 35)) * 0.9;
    canvas.translate(0, shift);
    final sky = Paint()..color = const Color(0xFF1A3E86);
    final ground = Paint()..color = const Color(0xFF10233A);
    canvas.drawRect(Rect.fromLTWH(-200, -200, 400, 200), sky);
    canvas.drawRect(const Rect.fromLTWH(-200, 0, 400, 200), ground);
    final line = Paint()
      ..color = const Color(0xAAFFFFFF)
      ..strokeWidth = 1.2;
    canvas.drawLine(const Offset(-200, 0), const Offset(200, 0), line);
    canvas.restore();
  }

  void _paintVehicle(Canvas canvas, Size size) {
    final rollR = -roll * math.pi / 180;
    final pitchR = pitch * math.pi / 180;
    final yawR = yaw * math.pi / 180;
    final cx = size.width / 2;
    final cy = size.height / 2 + 2;

    final ordered = <(double z, Path path, Color color)>[];
    for (final face in _faces) {
      final path = Path();
      var zSum = 0.0;
      for (var i = 0; i < face.pts.length; i++) {
        final p = _project(face.pts[i], rollR, pitchR, yawR);
        zSum += p.z;
        final o = Offset(cx + p.x, cy - p.y);
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      path.close();
      ordered.add((zSum / face.pts.length, path, face.color));
    }
    ordered.sort((a, b) => a.$1.compareTo(b.$1));
    for (final face in ordered) {
      canvas.drawPath(face.$2, Paint()..color = face.$3);
      canvas.drawPath(
        face.$2,
        Paint()
          ..color = const Color(0x66FFF4C8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  /// CSS order on the control page: rotateZ(-roll), then rotateY(yaw), then rotateX(pitch).
  _Vec _project(_Vec p, double roll, double pitch, double yaw) {
    final x1 = p.x * math.cos(roll) - p.y * math.sin(roll);
    final y1 = p.x * math.sin(roll) + p.y * math.cos(roll);
    final z1 = p.z;
    final x2 = x1 * math.cos(yaw) + z1 * math.sin(yaw);
    final y2 = y1;
    final z2 = -x1 * math.sin(yaw) + z1 * math.cos(yaw);
    final x3 = x2;
    final y3 = y2 * math.cos(pitch) - z2 * math.sin(pitch);
    final z3 = y2 * math.sin(pitch) + z2 * math.cos(pitch);
    final s = 1.55 * (220 / (220 - z3));
    return _Vec(x3 * s, y3 * s, z3);
  }

  @override
  bool shouldRepaint(covariant _AttitudePainter oldDelegate) =>
      oldDelegate.roll != roll ||
      oldDelegate.pitch != pitch ||
      oldDelegate.yaw != yaw;
}
