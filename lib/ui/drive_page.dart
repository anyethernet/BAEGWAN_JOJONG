import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../net/pipe_link.dart';
import 'attitude_badge.dart';
import 'hold_throttle.dart';
import 'joystick.dart';
import 'settings_panel.dart';

class DrivePage extends StatefulWidget {
  const DrivePage({super.key, required this.link});

  final PipeLink link;

  @override
  State<DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends State<DrivePage> with WidgetsBindingObserver {
  bool _settings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.link.loadCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_settings) widget.link.inputEnabled = true;
      return;
    }
    widget.link.inputEnabled = false;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      widget.link.allStop();
    }
  }

  void _setSettings(bool open) {
    setState(() => _settings = open);
    widget.link.inputEnabled = !open;
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFF070D1C),
      body: ListenableBuilder(
        listenable: link,
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              _VideoLayer(link: link),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final compact = box.maxHeight < 380;
                    final stick = compact ? 108.0 : 136.0;
                    final ledSize = compact ? 40.0 : 46.0;
                    return Stack(
                      children: [
                        Positioned(
                          left: 10,
                          bottom: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _thrustReadout([
                                ('M1', link.thrPct(0)),
                                ('M2', link.thrPct(1)),
                              ]),
                              const SizedBox(height: 2),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Joystick(
                                    key: const Key('stick-move'),
                                    label: link.liftArmed ? '전진 · 좌우' : '상승 후 전진',
                                    size: stick,
                                    enabled: link.inputEnabled && link.liftArmed,
                                    resetToken: link.moveReset,
                                    onChanged: (v) => link.setMove(v.dx, v.dy),
                                    onReleased: link.releaseMove,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 10, bottom: 18),
                                    child: _stopButton(link),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 10,
                          bottom: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _thrustReadout([
                                ('M3', link.thrPct(2)),
                                ('M4', link.thrPct(3)),
                                ('M5', link.thrPct(4)),
                              ]),
                              const SizedBox(height: 2),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(right: 10, bottom: 18),
                                    child: Column(
                                      children: [
                                        _ledButton(link, 1, ledSize),
                                        const SizedBox(height: 8),
                                        _ledButton(link, 2, ledSize),
                                      ],
                                    ),
                                  ),
                                  HoldThrottle(
                                    key: const Key('stick-vert'),
                                    size: stick,
                                    enabled: link.inputEnabled,
                                    resetToken: link.stickReset,
                                    onChanged: link.setLift,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 8,
                          right: 8,
                          top: 6,
                          child: _topBar(link, compact),
                        ),
                        if (link.toast != null)
                          Positioned(
                            left: 16,
                            right: 16,
                            top: compact ? 78 : 96,
                            child: Center(child: _toast(link)),
                          ),
                      ],
                    );
                  },
                ),
              ),
              if (_settings)
                SettingsPanel(
                  link: link,
                  onClose: () => _setSettings(false),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _topBar(PipeLink link, bool compact) {
    final rec = _recLabel(link);
    final counter = link.counterM;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _roundIcon(
          key: const Key('settings-button'),
          icon: Icons.settings,
          onTap: () => _setSettings(true),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _pill(
              link.socketOpen
                  ? (link.telemetryFresh ? '연결' : '대기')
                  : '끊김',
              link.socketOpen && link.telemetryFresh
                  ? const Color(0xFF14532D)
                  : const Color(0xFF5A2A12),
            ),
            const SizedBox(height: 4),
            _pill(
              counter == null ? '— m' : '${counter.toStringAsFixed(2)} m',
              const Color(0xCC15284E),
            ),
            if (rec.isNotEmpty) ...[
              const SizedBox(height: 4),
              _pill(rec, const Color(0xFF8B1F2F)),
            ],
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                _camSlider(
                  '밝기',
                  link.camBrightness,
                  0,
                  255,
                  (v) => link.updateCamera(brightness: v),
                ),
                _camSlider(
                  '게인',
                  link.camGain,
                  0,
                  255,
                  (v) => link.updateCamera(gain: v),
                ),
                _camSlider(
                  '노출',
                  link.camExposure,
                  1,
                  1000,
                  (v) => link.updateCamera(exposure: v),
                ),
              ],
            ),
          ),
        ),
        AttitudeBadge(
          attitude: link.attitude,
          width: compact ? 112 : 132,
          height: compact ? 96 : 112,
        ),
      ],
    );
  }

  Widget _camSlider(
    String label,
    int value,
    double min,
    double max,
    ValueChanged<int> onChanged,
  ) {
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xE6FFFFFF),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                shadows: [Shadow(color: Color(0xE6000000), blurRadius: 6)],
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                trackHeight: 2,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: Color(0xB37DD3FC),
                inactiveTrackColor: Color(0x40FFFFFF),
                thumbColor: Color(0xD9FFFFFF),
                overlayColor: Color(0x337DD3FC),
              ),
              child: Slider(
                value: value.toDouble().clamp(min, max),
                min: min,
                max: max,
                onChanged: (v) => onChanged(v.round()),
              ),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$value',
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Color(0xD9FFFFFF),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
                shadows: [Shadow(color: Color(0xE6000000), blurRadius: 6)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thrustReadout(List<(String, int?)> items) {
    return IgnorePointer(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Text(
              '${items[i].$1} ${items[i].$2 ?? 0}%',
              style: TextStyle(
                color: (items[i].$2 ?? 0) > 0
                    ? const Color(0xD97DD3FC)
                    : const Color(0xA6FFFFFF),
                fontSize: 15,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
                shadows: const [
                  Shadow(color: Color(0xE6000000), blurRadius: 8),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ledButton(PipeLink link, int ch, double size) {
    final on = link.ledOn(ch);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: on ? const Color(0xF0C49212) : const Color(0x66304066),
        shape: CircleBorder(
          side: BorderSide(
            color: on ? const Color(0xFFFFE08A) : const Color(0x99D6E4FF),
          ),
        ),
        child: InkWell(
          key: Key('led-$ch'),
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.selectionClick();
            link.toggleLed(ch);
          },
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: Text(
                '$ch',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: ch <= 2 ? 18 : 14,
                  shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 4)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stopButton(PipeLink link) {
    return Material(
      color: const Color(0xE08B1F2F),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('stop-button'),
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.heavyImpact();
          link.stopMove();
        },
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          child: Text(
            '정지',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _roundIcon({
    required Key key,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xB3101830),
      shape: const CircleBorder(side: BorderSide(color: Color(0x99D6E4FF))),
      child: InkWell(
        key: key,
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x66FFFFFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _toast(PipeLink link) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: link.toastError ? const Color(0xF04A1D24) : const Color(0xF0134330),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: link.toastError ? const Color(0xFFB04A56) : const Color(0xFF2F8F5A),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          link.toast ?? '',
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }

  String _recLabel(PipeLink link) {
    if (link.recordingBusy || link.videoFinalizing) return '변환 중';
    if (link.missionActive) return '기록 ${formatElapsed(link.missionElapsed)}';
    if (link.videoRecording) return '영상 REC';
    if (link.streamError != null && link.frame.value != null) return '영상 재연결';
    return '';
  }
}

class _VideoLayer extends StatelessWidget {
  const _VideoLayer({required this.link});

  final PipeLink link;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Uint8List?>(
      valueListenable: link.frame,
      builder: (context, bytes, _) {
        if (bytes == null) {
          return ColoredBox(
            color: const Color(0xFF070D1C),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  link.streamError ?? '영상 연결 중…\n${link.addressLabel}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFD6E4FF), fontSize: 16),
                ),
              ),
            ),
          );
        }
        return Image.memory(
          bytes,
          gaplessPlayback: true,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          filterQuality: FilterQuality.low,
        );
      },
    );
  }
}
