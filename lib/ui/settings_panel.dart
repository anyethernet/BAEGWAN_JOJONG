import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../net/pipe_link.dart';

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key, required this.link, required this.onClose});

  final PipeLink link;
  final VoidCallback onClose;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  late final TextEditingController _host;
  late final TextEditingController _label;
  String? _camError;
  List<PreflightItem>? _checks;
  bool _checking = false;

  static const _motors = ['M1 왼쪽', 'M2 오른쪽', 'M3 수직', 'M4 수직', 'M5 수직'];

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(text: widget.link.addressLabel);
    _label = TextEditingController(text: widget.link.missionLabel);
    unawaited(_loadCamera());
  }

  @override
  void dispose() {
    _host.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _loadCamera() async {
    try {
      await widget.link.loadCamera();
      if (!mounted) return;
      setState(() => _camError = null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _camError = '$e');
    }
  }

  Future<void> _connect() async {
    await widget.link.applyAddress(_host.text);
    if (!mounted) return;
    await widget.link.reconnect();
  }

  Future<void> _stopRecord() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기록 정지'),
        content: const Text('미션 기록과 영상 저장을 정지할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('정지'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(width: 16),
              Expanded(child: Text('영상 변환 중…\n최대 90초 걸릴 수 있습니다.')),
            ],
          ),
        ),
      ),
    );
    try {
      await widget.link.stopRecord();
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _preflight() async {
    setState(() => _checking = true);
    try {
      final items = await widget.link.preflight();
      if (!mounted) return;
      setState(() => _checks = items);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    final width = MediaQuery.sizeOf(context).width;
    final panelWidth = width < 520 ? width * 0.92 : 440.0;
    final active = link.missionActive;
    final dist = link.missionDistance;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            child: const ColoredBox(color: Color(0x99000000)),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: panelWidth,
          child: Material(
            color: const Color(0xF0121E3B),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '설정',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const _Head('연결'),
                    TextField(
                      controller: _host,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: '라즈베리파이 주소',
                        hintText: '192.168.1.157',
                        helperText: '포트가 다르면 192.168.1.157:8080',
                      ),
                      onSubmitted: (_) => _connect(),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        onPressed: _connect,
                        child: const Text('이 주소로 연결'),
                      ),
                    ),
                    const _Head('기록'),
                    TextField(
                      controller: _label,
                      enabled: !active,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: '라벨',
                        hintText: '예: pipeA_seg3',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: active || link.recordingBusy
                              ? null
                              : () => link.startRecord(_label.text),
                          child: const Text('기록 시작'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF8B1F2F),
                          ),
                          onPressed: (!active && !link.videoRecording) ||
                                  link.recordingBusy
                              ? null
                              : _stopRecord,
                          child: const Text('기록 정지'),
                        ),
                        OutlinedButton(
                          onPressed: _checking ? null : _preflight,
                          child: Text(_checking ? '점검 중…' : '상태 점검'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      active
                          ? '기록 중 · ${formatElapsed(link.missionElapsed)}'
                              ' · 샘플 ${link.missionSamples}'
                              '${link.missionLabel.isEmpty ? '' : ' · ${link.missionLabel}'}'
                              '${dist == null ? '' : ' · ${dist.toStringAsFixed(2)} m'}'
                          : (link.missionName.isEmpty
                              ? '미션: 대기'
                              : '마지막 기록 ${link.missionName}'),
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (link.videoRecording)
                      Text(
                        '영상 REC ${link.videoFile}',
                        style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 13),
                      ),
                    if (_checks != null) ...[
                      const SizedBox(height: 8),
                      for (final item in _checks!)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Icon(
                                item.ok ? Icons.check_circle : Icons.error,
                                size: 16,
                                color: item.ok
                                    ? const Color(0xFF3EC97A)
                                    : const Color(0xFFE26B78),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('${item.label} — ${item.detail}'),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const _Head('LED'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (var ch = 1; ch <= 2; ch++)
                          FilterChip(
                            label: Text('LED$ch'),
                            selected: link.ledOn(ch),
                            onSelected: (_) {
                              HapticFeedback.selectionClick();
                              link.toggleLed(ch);
                            },
                          ),
                      ],
                    ),
                    const _Head('추진기'),
                    for (var i = 0; i < _motors.length; i++) _motorRow(link, i),
                    const _Head('카메라'),
                    if (_camError != null)
                      Text(_camError!, style: const TextStyle(color: Color(0xFFFF8A8A))),
                    _slider('밝기', link.camBrightness, 0, 255, (v) {
                      link.updateCamera(brightness: v);
                    }),
                    _slider('게인', link.camGain, 0, 255, (v) {
                      link.updateCamera(gain: v);
                    }),
                    _slider('노출', link.camExposure, 1, 1000, (v) {
                      link.updateCamera(exposure: v);
                    }),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final p in const ['high', 'standard', 'low_latency'])
                          ChoiceChip(
                            label: Text(p == 'low_latency' ? 'Low Latency' : p),
                            selected: link.camProfile == p,
                            onSelected: (_) => link.setQuality(p),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: link.resetCameraSoft,
                          child: const Text('카메라 Soft 리셋'),
                        ),
                        OutlinedButton(
                          onPressed: link.syncRtc,
                          child: const Text('RTC 동기화'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '같은 Wi-Fi에서 라즈베리파이 주소로 접속합니다. 기본은 192.168.1.157 입니다.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFB7C6E6)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _motorRow(PipeLink link, int i) {
    final us = link.thrUs(i);
    final idle = link.thrIdle;
    final pct = link.thrPct(i);
    final running = us != null && us != idle;
    final target = link.thrTarget(i);
    var detail = us == null ? '—' : '$us µs';
    if (running) detail += ' · ${pct ?? '—'}%';
    if (target != null && target != us) {
      detail += target == idle ? ' → 정지' : ' → $target';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(_motors[i])),
          Expanded(
            child: Text(
              running ? detail : '정지',
              style: TextStyle(color: running ? const Color(0xFF7DD3FC) : null),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(
    String label,
    int value,
    double min,
    double max,
    ValueChanged<int> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 42, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: Slider(
            value: value.toDouble().clamp(min, max),
            min: min,
            max: max,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text('$value', textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: Color(0xFF9EC0FF),
        ),
      ),
    );
  }
}
