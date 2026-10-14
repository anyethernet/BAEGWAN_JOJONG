import 'dart:typed_data';

/// Pulls JPEG frames out of an MJPEG byte stream (`--frame` parts or raw SOI/EOI).
class MjpegParser {
  final List<int> _buf = <int>[];

  static const _max = 1500000;

  List<Uint8List> add(List<int> chunk) {
    if (chunk.isEmpty) return const [];
    _buf.addAll(chunk);
    final frames = <Uint8List>[];
    while (true) {
      final start = _find(_buf, 0, 0xFF, 0xD8);
      if (start < 0) {
        if (_buf.length > 1) {
          final keep = _buf.last == 0xFF ? 1 : 0;
          _buf.removeRange(0, _buf.length - keep);
        }
        break;
      }
      if (start > 0) _buf.removeRange(0, start);
      final end = _find(_buf, 2, 0xFF, 0xD9);
      if (end < 0) {
        if (_buf.length > _max) _buf.clear();
        break;
      }
      frames.add(Uint8List.fromList(_buf.sublist(0, end + 2)));
      _buf.removeRange(0, end + 2);
    }
    return frames;
  }

  static int _find(List<int> b, int from, int a, int c) {
    for (var i = from; i < b.length - 1; i++) {
      if (b[i] == a && b[i + 1] == c) return i;
    }
    return -1;
  }
}
