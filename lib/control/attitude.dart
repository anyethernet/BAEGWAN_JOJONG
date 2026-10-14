import 'dart:math' as math;

class Attitude {
  const Attitude(this.roll, this.pitch, this.yaw);

  final double roll;
  final double pitch;
  final double yaw;

  static const zero = Attitude(0, 0, 0);

  /// Same selection rules as `extractAttitudeDeg` on the Pi control page.
  factory Attitude.fromTelemetry(Map<String, dynamic> t) {
    final imu = _map(t['imu']);
    final rollRaw = _pick([t['roll'], imu?['roll'], t['r'], imu?['r']]);
    final pitchRaw = _pick([t['pitch'], imu?['pitch'], t['p'], imu?['p']]);
    final yawRaw = _pick([
      t['yaw'],
      imu?['yaw'],
      t['heading'],
      imu?['heading'],
    ]);
    final ax = _pick([imu?['ax'], t['ax']]);
    final ay = _pick([imu?['ay'], t['ay']]);
    final az = _pick([imu?['az'], t['az']]);
    final hasAccel = ax != null && ay != null && az != null;

    if (rollRaw != null && pitchRaw != null) {
      if (hasAccel && (rollRaw - pitchRaw).abs() < 0.05) {
        return Attitude(
          math.atan2(ay, az) * 180 / math.pi,
          math.atan2(-ax, math.sqrt(ay * ay + az * az)) * 180 / math.pi,
          yawRaw ?? 0,
        );
      }
      return Attitude(rollRaw, pitchRaw, yawRaw ?? 0);
    }
    if (hasAccel) {
      return Attitude(
        math.atan2(ay, az) * 180 / math.pi,
        math.atan2(-ax, math.sqrt(ay * ay + az * az)) * 180 / math.pi,
        yawRaw ?? 0,
      );
    }
    return Attitude(0, 0, yawRaw ?? 0);
  }
}

Map<String, dynamic>? _map(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

double? _pick(List<Object?> values) {
  for (final v in values) {
    final n = asDouble(v);
    if (n != null) return n;
  }
  return null;
}

double? asDouble(Object? v) {
  if (v is num) {
    final n = v.toDouble();
    return n.isFinite ? n : null;
  }
  if (v is String && v.trim().isNotEmpty) {
    final n = double.tryParse(v.trim());
    if (n != null && n.isFinite) return n;
  }
  return null;
}
