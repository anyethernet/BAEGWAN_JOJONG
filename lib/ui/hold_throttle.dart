import 'package:flutter/material.dart';

/// Vertical lift setting that stays where it is released.
/// The bottom is 0%. Any lift above that holds from 10% to 100%.
class HoldThrottle extends StatefulWidget {
  const HoldThrottle({
    super.key,
    required this.onChanged,
    this.enabled = true,
    this.resetToken = 0,
    this.size = 148,
  });

  final ValueChanged<int> onChanged;
  final bool enabled;
  final int resetToken;
  final double size;

  @override
  State<HoldThrottle> createState() => _HoldThrottleState();
}

class _HoldThrottleState extends State<HoldThrottle> {
  bool _active = false;
  int _pct = 0;

  @override
  void didUpdateWidget(HoldThrottle oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reset = widget.resetToken != oldWidget.resetToken;
    final disabled = oldWidget.enabled && !widget.enabled;
    if (reset || disabled) {
      _active = false;
      _pct = 0;
    }
  }

  void _apply(Offset local) {
    final pad = widget.size * 0.12;
    final span = widget.size - pad * 2;
    final t = ((local.dy - pad) / span).clamp(0.0, 1.0);
    var pct = ((1 - t) * 100).round();
    if (pct > 0 && pct < 10) pct = 10;
    if (pct == _pct) return;
    setState(() => _pct = pct);
    widget.onChanged(pct);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final pad = size * 0.12;
    final knob = size * 0.22;
    final travel = size - pad * 2 - knob;
    final top = pad + (1 - _pct / 100) * travel;
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
          onPointerUp: (_) => _active = false,
          onPointerCancel: (_) => _active = false,
          child: SizedBox(
            width: size * 0.72,
            height: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.18),
                color: const Color(0x59101830),
                border: Border.all(color: const Color(0x99D6E4FF), width: 1.4),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: size * 0.36 - 1,
                    top: pad,
                    bottom: pad,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(color: Color(0x55FFFFFF)),
                      child: SizedBox(width: 2),
                    ),
                  ),
                  Positioned(
                    left: size * 0.36 - knob / 2,
                    top: top,
                    child: Container(
                      width: knob,
                      height: knob,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.enabled
                            ? (_pct >= 10
                                ? const Color(0xCC1C8FBF)
                                : const Color(0xCC2B5FC8))
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
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: FittedBox(
                          child: Text(
                            '$_pct',
                            style: const TextStyle(
                              color: Color(0xFFF4F8FF),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '상승',
          style: TextStyle(
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
