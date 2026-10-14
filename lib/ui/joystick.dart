import 'package:flutter/material.dart';

/// Transparent stick. [onChanged] reports x right and y up, each in -1..1.
class Joystick extends StatefulWidget {
  const Joystick({
    super.key,
    required this.label,
    required this.onChanged,
    required this.onReleased,
    this.verticalOnly = false,
    this.enabled = true,
    this.resetToken = 0,
    this.size = 148,
  });

  final String label;
  final ValueChanged<Offset> onChanged;
  final VoidCallback onReleased;
  final bool verticalOnly;
  final bool enabled;
  final int resetToken;
  final double size;

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  bool _active = false;
  double _x = 0;
  double _y = 0;

  @override
  void didUpdateWidget(Joystick oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reset = widget.resetToken != oldWidget.resetToken;
    final disabled = oldWidget.enabled && !widget.enabled;
    if (reset || disabled) {
      _active = false;
      _x = 0;
      _y = 0;
    }
  }

  void _apply(Offset local) {
    final half = widget.size / 2;
    var nx = ((local.dx - half) / half).clamp(-1.0, 1.0).toDouble();
    var ny = -((local.dy - half) / half).clamp(-1.0, 1.0).toDouble();
    if (widget.verticalOnly) nx = 0;
    setState(() {
      _x = nx;
      _y = ny;
    });
    widget.onChanged(Offset(nx, ny));
  }

  void _end() {
    final wasHeld = _active || _x != 0 || _y != 0;
    _active = false;
    if (_x != 0 || _y != 0) {
      setState(() {
        _x = 0;
        _y = 0;
      });
    }
    if (wasHeld) widget.onReleased();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final travel = size * 0.32;
    final knob = size * 0.34;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: widget.enabled
              ? (e) {
                  _active = true;
                  _apply(e.localPosition);
                }
              : null,
          onPointerMove: (e) {
            if (_active && widget.enabled) _apply(e.localPosition);
          },
          onPointerUp: (_) => _end(),
          onPointerCancel: (_) => _end(),
          child: SizedBox(
            width: size,
            height: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.18),
                color: const Color(0x59101830),
                border: Border.all(color: const Color(0x99D6E4FF), width: 1.4),
              ),
              child: Stack(
                children: [
                  const Positioned.fill(child: CustomPaint(painter: _CrossPainter())),
                  Positioned(
                    left: size / 2 + _x * travel - knob / 2,
                    top: size / 2 - _y * travel - knob / 2,
                    child: Container(
                      width: knob,
                      height: knob,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.enabled
                            ? const Color(0xCC2B5FC8)
                            : const Color(0x883A4A68),
                        border: Border.all(color: const Color(0xEEF4F8FF)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.label,
          style: const TextStyle(
            color: Color(0xE6F2F7FF),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(color: Color(0xCC000000), blurRadius: 6)],
          ),
        ),
      ],
    );
  }
}

class _CrossPainter extends CustomPainter {
  const _CrossPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 1;
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawLine(Offset(c.dx, 14), Offset(c.dx, size.height - 14), paint);
    canvas.drawLine(Offset(14, c.dy), Offset(size.width - 14, c.dy), paint);
    canvas.drawCircle(c, 3, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
