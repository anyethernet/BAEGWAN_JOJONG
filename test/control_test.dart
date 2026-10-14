import 'dart:typed_data';

import 'package:dronctl_app/control/attitude.dart';
import 'package:dronctl_app/control/stick_mix.dart';
import 'package:dronctl_app/net/mjpeg_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stick mix matches the Pi control page', () {
    expect(
      StickMix.fromStick(moveX: 0, moveY: 0, liftPct: 0),
      StickMix.zero,
    );
    expect(
      StickMix.fromStick(moveX: 0, moveY: 1, liftPct: 0),
      StickMix.zero,
    );
    expect(
      StickMix.fromStick(moveX: 1, moveY: 1, liftPct: 9),
      const StickMix(0, 0, 26),
    );
    expect(
      StickMix.fromStick(moveX: 0, moveY: 1, liftPct: 10),
      const StickMix(255, 255, 26),
    );
    expect(
      StickMix.fromStick(moveX: 1, moveY: 0, liftPct: 50),
      const StickMix(255, 0, 128),
    );
    expect(
      StickMix.fromStick(moveX: -1, moveY: 0, liftPct: 50),
      const StickMix(0, 255, 128),
    );
    expect(
      StickMix.fromStick(moveX: 0, moveY: -1, liftPct: 100),
      const StickMix(0, 0, 255),
    );
    expect(StickMix.holdLift(0), 0);
    expect(StickMix.holdLift(4), 10);
    expect(StickMix.holdLift(100), 100);
  });

  test('attitude prefers fused angles and falls back to accel', () {
    final fused = Attitude.fromTelemetry({
      'roll': 10,
      'pitch': -4,
      'yaw': 30,
    });
    expect(fused.roll, 10);
    expect(fused.pitch, -4);
    expect(fused.yaw, 30);

    final level = Attitude.fromTelemetry({
      'imu': {'ax': 0, 'ay': 0, 'az': 1},
    });
    expect(level.roll, closeTo(0, 0.001));
    expect(level.pitch, closeTo(0, 0.001));
  });

  test('mjpeg parser extracts a jpeg split across chunks', () {
    final jpg = Uint8List.fromList([0xFF, 0xD8, 0x11, 0x22, 0xFF, 0xD9]);
    final chunk = <int>[
      ...'--frame\r\n'.codeUnits,
      ...jpg,
      ...'\r\n'.codeUnits,
    ];
    final parser = MjpegParser();
    expect(parser.add(chunk.sublist(0, 8)), isEmpty);
    final frames = parser.add(chunk.sublist(8));
    expect(frames, hasLength(1));
    expect(frames.single, jpg);
  });
}
