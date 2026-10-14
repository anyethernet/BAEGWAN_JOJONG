import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../control/attitude.dart';
import '../control/stick_mix.dart';
import 'mjpeg_parser.dart';

class PreflightItem {
  const PreflightItem(this.label, this.ok, this.detail);

  final String label;
  final bool ok;
  final String detail;
}

class CamControls {
  const CamControls({
    required this.brightness,
    required this.gain,
    required this.exposure,
    required this.profile,
  });

  final int brightness;
  final int gain;
  final int exposure;
  final String profile;
}

/// Wi-Fi client for the pipeline Pi (port 80 proxies `/api` and `/ws`).
class PipeLink extends ChangeNotifier {
  PipeLink({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final frame = ValueNotifier<Uint8List?>(null);

  String _hostName = '192.168.1.157';
  int _port = 80;

  bool _socketOpen = false;
  bool _inputEnabled = true;
  int _stickReset = 0;
  int _moveReset = 0;
  int _session = 0;
  int _cmdGen = 0;

  double _moveX = 0;
  double _moveY = 0;
  int _liftPct = 0;
  StickMix _last = StickMix.zero;
  DateTime _lastAt = DateTime.now();
  bool _motorBusy = false;
  StickMix? _queued;
  int _queuedGen = 0;

  Map<String, dynamic> _telemetry = {};
  Map<String, dynamic> _media = {};
  Map<String, dynamic> _mission = {};
  DateTime? _telemetryAt;
  final Map<int, (bool on, DateTime at)> _ledHold = {};

  String? _toast;
  bool _toastError = false;
  String? _streamError;
  bool _recordingBusy = false;

  int camBrightness = 128;
  int camGain = 64;
  int camExposure = 200;
  String camProfile = 'standard';
  bool camReady = false;
  Timer? _camTimer;

  Timer? _tick;
  Timer? _freshTimer;
  Timer? _toastTimer;
  Timer? _reconnectTimer;
  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  HttpClient? _mjpegClient;

  String get host => _hostName;
  int get port => _port;
  String get addressLabel => _port == 80 ? _hostName : '$_hostName:$_port';
  bool get socketOpen => _socketOpen;
  bool get inputEnabled => _inputEnabled;
  int get stickReset => _stickReset;
  int get moveReset => _moveReset;
  int get liftPct => _liftPct;
  bool get liftArmed => _liftPct >= 10;
  bool get telemetryFresh =>
      _telemetryAt != null &&
      DateTime.now().difference(_telemetryAt!) < const Duration(seconds: 3);

  Attitude get attitude => Attitude.fromTelemetry(_telemetry);
  double? get counterM => asDouble(_telemetry['counter_m']);
  String get rtcText {
    final rtc = _telemetry['rtc'];
    if (rtc == null || rtc == 0 || rtc == '0' || '$rtc'.isEmpty) return '';
    return '$rtc';
  }

  bool get videoRecording => _media['video_recording'] == true;
  bool get videoFinalizing => _media['video_finalizing'] == true;
  String get videoFile => _baseName(_media['video_file']);

  bool get missionActive => _mission['active'] == true;
  String get missionLabel => '${_mission['label'] ?? ''}';
  String get missionName => _baseName(_mission['name']);
  double get missionElapsed => asDouble(_mission['elapsed_sec']) ?? 0;
  double? get missionDistance => asDouble(_mission['distance_m']);
  int get missionSamples => (_mission['telemetry_count'] as num?)?.round() ?? 0;

  String? get toast => _toast;
  bool get toastError => _toastError;
  String? get streamError => _streamError;
  bool get recordingBusy => _recordingBusy;

  int get thrIdle => (asDouble(_telemetry['thr_idle_us']) ?? 2500).round();

  bool ledOn(int ch) {
    final hold = _ledHold[ch];
    if (hold != null &&
        DateTime.now().difference(hold.$2) < const Duration(seconds: 2)) {
      return hold.$1;
    }
    final led = _telemetry['led'];
    if (led is Map) return _asBool(led['$ch'] ?? led[ch]);
    return false;
  }

  int? thrUs(int i) => _atInt(_telemetry['thr_us'], i);
  int? thrTarget(int i) => _atInt(_telemetry['thr_target_us'], i);
  int? thrPct(int i) => _atInt(_telemetry['thr_pct'], i);

  set inputEnabled(bool value) {
    final changed = _inputEnabled != value;
    _inputEnabled = value;
    if (!value) {
      _moveX = 0;
      _moveY = 0;
      _liftPct = 0;
      _flushStick(force: true);
    }
    if (changed) notifyListeners();
  }

  Future<void> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _hostName = prefs.getString('pipe_host') ?? _hostName;
    _port = prefs.getInt('pipe_port') ?? _port;
    notifyListeners();
  }

  Future<void> applyAddress(String raw) async {
    _parseAddress(raw);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pipe_host', _hostName);
    await prefs.setInt('pipe_port', _port);
    notifyListeners();
  }

  void start() {
    _session++;
    final session = _session;
    _streamError = null;
    _connectWs(session);
    unawaited(_mjpeg(session));
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_session == session) _flushStick();
    });
    _freshTimer?.cancel();
    _freshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_session == session) notifyListeners();
    });
    notifyListeners();
  }

  Future<void> reconnect({bool sendStop = true}) async {
    await stop(sendStop: sendStop);
    frame.value = null;
    start();
  }

  Future<void> stop({bool sendStop = false}) async {
    final client = _mjpegClient;
    _session++;
    _tick?.cancel();
    _freshTimer?.cancel();
    _reconnectTimer?.cancel();
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _ws?.sink.close();
    } catch (_) {}
    _ws = null;
    client?.close(force: true);
    _socketOpen = false;
    notifyListeners();
    if (sendStop) {
      try {
        await _post('/api/all_stop', {});
      } catch (_) {}
    }
  }

  void setMove(double x, double y) {
    if (!_inputEnabled || _liftPct < 10) return;
    _moveX = x.clamp(-1.0, 1.0).toDouble();
    _moveY = y.clamp(-1.0, 1.0).toDouble();
  }

  void setLift(int pct) {
    if (!_inputEnabled) return;
    final next = StickMix.holdLift(pct);
    if (next == _liftPct) return;
    _liftPct = next;
    if (next < 10) {
      _moveX = 0;
      _moveY = 0;
    }
    notifyListeners();
    _flushStick();
  }

  void releaseMove() {
    _moveX = 0;
    _moveY = 0;
    _flushStick(force: true);
  }

  /// Stops the forward thrusters only. Lift stays at the held percent.
  void stopMove() {
    _moveReset++;
    _moveX = 0;
    _moveY = 0;
    notifyListeners();
    _flushStick(force: true);
    _toastMsg('M1·M2 정지');
  }

  Future<void> allStop() async {
    _stickReset++;
    _moveReset++;
    _moveX = 0;
    _moveY = 0;
    _liftPct = 0;
    _cmdGen++;
    _last = StickMix.zero;
    _lastAt = DateTime.now();
    notifyListeners();
    try {
      await _post('/api/all_stop', {});
      _toastMsg('정지');
    } catch (e) {
      _toastMsg('정지 실패: $e', error: true);
    }
  }

  Future<void> toggleLed(int ch) async {
    final next = !ledOn(ch);
    _ledHold[ch] = (next, DateTime.now());
    notifyListeners();
    try {
      await _post('/api/led', {'ch': ch, 'on': next});
      _toastMsg('LED$ch ${next ? 'ON' : 'OFF'}');
    } catch (e) {
      _ledHold.remove(ch);
      _toastMsg('LED$ch 실패: $e', error: true);
    }
  }

  Future<void> startRecord(String label) async {
    if (_recordingBusy) return;
    _recordingBusy = true;
    notifyListeners();
    try {
      final data = await _post('/api/mission/start', {'label': label.trim()});
      final mission = data['mission'];
      if (mission is Map) _mission = Map<String, dynamic>.from(mission);
      _toastMsg('미션 기록 시작');
      if (!videoRecording && !videoFinalizing) {
        try {
          await _post('/api/video/start', {});
          _toastMsg('영상 저장 시작');
        } catch (e) {
          _toastMsg('영상 저장 시작 실패: $e', error: true);
        }
      }
    } catch (e) {
      _toastMsg('미션 시작 실패: $e', error: true);
    } finally {
      _recordingBusy = false;
      notifyListeners();
    }
  }

  Future<void> stopRecord() async {
    if (_recordingBusy) return;
    _recordingBusy = true;
    notifyListeners();
    final wasVideo = videoRecording;
    try {
      final data = await _post('/api/mission/stop', {});
      final mission = data['mission'];
      if (mission is Map) _mission = Map<String, dynamic>.from(mission);
      _toastMsg('영상 변환 중… (최대 90초)');
      final stopped = await _post(
        '/api/video/stop',
        {},
        timeout: const Duration(seconds: 100),
      );
      final files = stopped['files'];
      if (files is List && files.isNotEmpty) {
        _toastMsg('저장됨: ${files.join(', ')}');
      } else if (wasVideo) {
        _toastMsg('미션 종료. 영상 파일을 확인하세요.', error: true);
      } else {
        _toastMsg('미션 기록 종료');
      }
    } catch (e) {
      _toastMsg('기록 정지 실패: $e', error: true);
    } finally {
      _recordingBusy = false;
      notifyListeners();
    }
  }

  Future<List<PreflightItem>> preflight() async {
    var media = _media;
    try {
      final health = await _get('/api/health');
      if (health['media'] is Map) {
        media = Map<String, dynamic>.from(health['media'] as Map);
      }
    } catch (_) {}

    var camOk = false;
    try {
      final res = await _http
          .get(_uri('/api/camera/controls'))
          .timeout(const Duration(seconds: 6));
      camOk = res.statusCode == 200;
    } catch (_) {}

    final fresh = telemetryFresh;
    final rtc = rtcText;
    final counter = counterM;
    final leds = [1, 2].where(ledOn).map((c) => 'LED$c').join(', ');
    final videoOn = media['video_recording'] == true;
    return [
      PreflightItem('시리얼 텔레메트리', fresh, fresh ? '수신 중' : '최근 데이터 없음'),
      PreflightItem('RTC', rtc.isNotEmpty, rtc.isEmpty ? '값 없음' : rtc),
      PreflightItem(
        '카운터',
        counter != null,
        counter == null ? '값 없음' : '${counter.toStringAsFixed(2)} m',
      ),
      PreflightItem('카메라 컨트롤', camOk, camOk ? 'v4l2 응답' : '응답 없음'),
      PreflightItem(
        '영상 녹화',
        videoOn,
        videoOn ? _baseName(media['video_file']).ifEmpty('REC') : '정지',
      ),
      PreflightItem('LED', leds.isNotEmpty, leds.isEmpty ? '전부 OFF' : leds),
    ];
  }

  Future<void> loadCamera() async {
    try {
      final cam = await fetchCamera();
      camBrightness = cam.brightness;
      camGain = cam.gain;
      camExposure = cam.exposure;
      camProfile = cam.profile;
      camReady = true;
      notifyListeners();
    } catch (_) {}
  }

  void updateCamera({int? brightness, int? gain, int? exposure}) {
    if (brightness != null) camBrightness = brightness.clamp(0, 255).toInt();
    if (gain != null) camGain = gain.clamp(0, 255).toInt();
    if (exposure != null) camExposure = exposure.clamp(1, 1000).toInt();
    notifyListeners();
    _camTimer?.cancel();
    _camTimer = Timer(const Duration(milliseconds: 120), () {
      unawaited(
        applyCamera(
          brightness: camBrightness,
          gain: camGain,
          exposure: camExposure,
        ),
      );
    });
  }

  Future<CamControls> fetchCamera() async {
    final controls = await _get('/api/camera/controls');
    final quality = await _get('/api/camera/quality');
    return CamControls(
      brightness: (controls['brightness'] as num?)?.round() ?? 128,
      gain: (controls['gain'] as num?)?.round() ?? 64,
      exposure: (controls['exposure_time_absolute'] as num?)?.round() ?? 200,
      profile: '${quality['profile'] ?? 'standard'}',
    );
  }

  Future<void> applyCamera({
    required int brightness,
    required int gain,
    required int exposure,
  }) async {
    try {
      await _post('/api/camera/controls', {
        'brightness': brightness,
        'gain': gain,
        'exposure_time_absolute': exposure,
      });
    } catch (e) {
      _toastMsg('카메라 설정 실패: $e', error: true);
    }
  }

  Future<void> setQuality(String profile) async {
    camProfile = profile;
    notifyListeners();
    try {
      await _post('/api/camera/quality', {'profile': profile});
      _mjpegClient?.close(force: true);
      _toastMsg('화질: $profile');
    } catch (e) {
      _toastMsg('화질 변경 실패: $e', error: true);
    }
  }

  Future<void> resetCameraSoft() async {
    try {
      await _post('/api/camera/reset', {'level': 'soft'});
      _mjpegClient?.close(force: true);
      _toastMsg('카메라 Soft 리셋');
    } catch (e) {
      _toastMsg('카메라 리셋 실패: $e', error: true);
    }
  }

  Future<void> syncRtc() async {
    try {
      await _post('/api/sync_time', {
        'unix': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });
      _toastMsg('RTC 동기화 요청');
    } catch (e) {
      _toastMsg('RTC 동기화 실패: $e', error: true);
    }
  }

  @override
  void dispose() {
    _session++;
    _tick?.cancel();
    _freshTimer?.cancel();
    _toastTimer?.cancel();
    _camTimer?.cancel();
    _reconnectTimer?.cancel();
    _wsSub?.cancel();
    _mjpegClient?.close(force: true);
    _http.close();
    frame.dispose();
    super.dispose();
  }

  void _connectWs(int session) {
    if (_session != session) return;
    _reconnectTimer?.cancel();
    final channel = WebSocketChannel.connect(_wsUri());
    _ws = channel;
    _wsSub = channel.stream.listen(
      (data) {
        if (_session != session) return;
        _onMessage(data);
      },
      onError: (_) {
        if (_session != session) return;
        _socketOpen = false;
        notifyListeners();
        _scheduleReconnect(session);
      },
      onDone: () {
        if (_session != session) return;
        _socketOpen = false;
        notifyListeners();
        _scheduleReconnect(session);
      },
      cancelOnError: true,
    );
    unawaited(
      channel.ready.then(
        (_) {
          if (_session != session) return;
          _socketOpen = true;
          notifyListeners();
        },
        onError: (_) {},
      ),
    );
  }

  void _scheduleReconnect(int session) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (_session == session) _connectWs(session);
    });
  }

  void _onMessage(Object? data) {
    final text = switch (data) {
      String s => s,
      List<int> bytes => utf8.decode(bytes),
      _ => null,
    };
    if (text == null || text.isEmpty) return;
    final decoded = jsonDecode(text);
    if (decoded is! Map) return;
    final map = Map<String, dynamic>.from(decoded);
    if (map['telemetry'] is Map) {
      _telemetry = Map<String, dynamic>.from(map['telemetry'] as Map);
      _telemetryAt = DateTime.now();
    }
    if (map['media'] is Map) {
      _media = Map<String, dynamic>.from(map['media'] as Map);
    }
    if (map['mission'] is Map) {
      _mission = Map<String, dynamic>.from(map['mission'] as Map);
    }
    _socketOpen = true;
    notifyListeners();
  }

  Future<void> _mjpeg(int session) async {
    while (_session == session) {
      final parser = MjpegParser();
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      _mjpegClient = client;
      try {
        final req = await client.getUrl(
          _uri('/api/camera/mjpeg').replace(
            queryParameters: {
              't': '${DateTime.now().millisecondsSinceEpoch}',
            },
          ),
        );
        req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        final res = await req.close().timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) {
          throw HttpException('HTTP ${res.statusCode}');
        }
        await for (final chunk in res.timeout(const Duration(seconds: 8))) {
          if (_session != session) return;
          final frames = parser.add(chunk);
          if (frames.isEmpty) continue;
          frame.value = frames.last;
          if (_streamError != null) {
            _streamError = null;
            notifyListeners();
          }
        }
      } catch (e) {
        if (_session != session) return;
        final msg = _short(e);
        if (_streamError != msg) {
          _streamError = msg;
          notifyListeners();
        }
      } finally {
        client.close(force: true);
      }
      if (_session != session) return;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  void _flushStick({bool force = false}) {
    final cmd = StickMix.fromStick(
      moveX: _moveX,
      moveY: _moveY,
      liftPct: _liftPct,
    );
    final now = DateTime.now();
    final same = cmd == _last;
    final keepAlive = !cmd.idle &&
        now.difference(_lastAt) >= const Duration(milliseconds: 400);
    if (!force && same && !keepAlive) return;
    if (cmd.idle && same) return;
    _last = cmd;
    _lastAt = now;
    unawaited(_postMotor(cmd));
  }

  Future<void> _postMotor(StickMix cmd) async {
    final gen = _cmdGen;
    if (_motorBusy) {
      _queued = cmd;
      _queuedGen = gen;
      return;
    }
    _motorBusy = true;
    try {
      if (gen == _cmdGen) {
        await _post(
          '/api/motor',
          {'left': cmd.left, 'right': cmd.right, 'vertical': cmd.vertical},
          timeout: const Duration(milliseconds: 2500),
        );
      }
    } catch (_) {
    } finally {
      _motorBusy = false;
      final queued = _queued;
      final queuedGen = _queuedGen;
      _queued = null;
      if (queued != null && queuedGen == _cmdGen && queued != cmd) {
        unawaited(_postMotor(queued));
      }
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final res = await _http
        .post(
          _uri(path),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(res.body.isEmpty ? 'HTTP ${res.statusCode}' : res.body);
    }
    if (res.body.isEmpty) return {};
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return {};
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final res = await _http.get(_uri(path)).timeout(const Duration(seconds: 6));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(res.body.isEmpty ? 'HTTP ${res.statusCode}' : res.body);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return {};
  }

  void _parseAddress(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return;
    s = s.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'), '');
    final slash = s.indexOf('/');
    if (slash >= 0) s = s.substring(0, slash);
    final colon = s.lastIndexOf(':');
    if (colon > 0 && s.indexOf(':') == colon) {
      final p = int.tryParse(s.substring(colon + 1));
      if (p != null && p > 0 && p < 65536) {
        _hostName = s.substring(0, colon);
        _port = p;
        return;
      }
    }
    _hostName = s;
    _port = 80;
  }

  Uri _uri(String path) =>
      Uri(scheme: 'http', host: _hostName, port: _port, path: path);

  Uri _wsUri() => Uri(scheme: 'ws', host: _hostName, port: _port, path: '/ws/status');

  void _toastMsg(String message, {bool error = false}) {
    _toast = message;
    _toastError = error;
    notifyListeners();
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2600), () {
      _toast = null;
      notifyListeners();
    });
  }

  static String _short(Object e) {
    final s = '$e';
    return s.length > 160 ? s.substring(0, 160) : s;
  }

  static String _baseName(Object? path) {
    final s = '${path ?? ''}';
    if (s.isEmpty) return '';
    final parts = s.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? s : parts.last;
  }

  static int? _atInt(Object? list, int i) {
    if (list is! List || i < 0 || i >= list.length) return null;
    final n = asDouble(list[i]);
    return n?.round();
  }

  static bool _asBool(Object? v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v == 'true' || v == '1';
    return false;
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

String formatElapsed(double sec) {
  final s = sec.isFinite ? sec.floor().clamp(0, 864000).toInt() : 0;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final ss = s % 60;
  final mm = m.toString().padLeft(2, '0');
  final sss = ss.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$sss' : '$mm:$sss';
}
