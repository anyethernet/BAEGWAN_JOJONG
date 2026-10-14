/// Thruster mix used by the Pi control page (`sendStickCommand` in index.html).
///
/// Move stick Y is forward only (pulling back is zero). X mixes the two
/// horizontal thrusters: right makes M1 (left) stronger.
/// Lift is a held percent. Horizontal thrust stays at zero until lift is
/// at least 10%, so the vehicle is off the floor before it drives forward.
class StickMix {
  const StickMix(this.left, this.right, this.vertical);

  final int left;
  final int right;
  final int vertical;

  static const zero = StickMix(0, 0, 0);

  bool get idle => left == 0 && right == 0 && vertical == 0;

  factory StickMix.fromStick({
    required double moveX,
    required double moveY,
    required int liftPct,
  }) {
    final lift = _liftUnit(liftPct);
    final armed = liftPct >= 10;
    final forward = armed ? _unit(moveY) : 0.0;
    final x = armed ? moveX : 0.0;
    return StickMix(
      (255 * _unit(forward + x)).round(),
      (255 * _unit(forward - x)).round(),
      (255 * lift).round(),
    );
  }

  /// 0 is off. Any positive command is held from 10% through 100%.
  static int holdLift(int pct) {
    if (pct <= 0) return 0;
    if (pct < 10) return 10;
    if (pct > 100) return 100;
    return pct;
  }

  static double _liftUnit(int pct) => holdLift(pct) / 100.0;

  static double _unit(double v) => v.clamp(0.0, 1.0).toDouble();

  @override
  bool operator ==(Object other) =>
      other is StickMix &&
      other.left == left &&
      other.right == right &&
      other.vertical == vertical;

  @override
  int get hashCode => Object.hash(left, right, vertical);
}
