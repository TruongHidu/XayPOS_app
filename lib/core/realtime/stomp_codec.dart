import 'dart:convert';

class StompFrame {
  const StompFrame(this.command, this.headers, this.body);
  final String command, body;
  final Map<String, String> headers;
}

/// Incremental UTF-8 STOMP 1.2 framing, including byte content-length and EOLs.
/// This adapter only implements the read-only subset used by this application.
class StompDecoder {
  final List<int> _buffer = [];
  static const maxFrameBytes = 256 * 1024;
  List<StompFrame> add(Object data) {
    _buffer.addAll(switch (data) {
      String text => utf8.encode(text),
      List<int> bytes => bytes,
      _ => throw const FormatException('Unsupported WebSocket data'),
    });
    if (_buffer.length > maxFrameBytes) {
      throw const FormatException('STOMP frame too large');
    }
    final frames = <StompFrame>[];
    while (_buffer.isNotEmpty) {
      while (_buffer.isNotEmpty &&
          (_buffer.first == 10 || _buffer.first == 13)) {
        _buffer.removeAt(0);
      }
      if (_buffer.isEmpty) break;
      final lines = <String>[];
      var offset = 0, bodyStart = -1;
      for (var i = 0; i < _buffer.length; i++) {
        if (_buffer[i] != 10) continue;
        final end = i > offset && _buffer[i - 1] == 13 ? i - 1 : i;
        final line = utf8.decode(_buffer.sublist(offset, end));
        offset = i + 1;
        if (line.isEmpty) {
          bodyStart = offset;
          break;
        }
        lines.add(line);
      }
      if (bodyStart < 0) break;
      if (lines.isEmpty) throw const FormatException('Missing STOMP command');
      final command = lines.first;
      final headers = <String, String>{};
      for (final line in lines.skip(1)) {
        final colon = line.indexOf(':');
        if (colon <= 0) throw const FormatException('Invalid STOMP header');
        String decode(String text) =>
            command == 'CONNECTED' ? text : _unescape(text);
        headers.putIfAbsent(
          decode(line.substring(0, colon)),
          () => decode(line.substring(colon + 1)),
        );
      }
      final lengthText = headers['content-length'];
      final length = lengthText == null ? null : int.tryParse(lengthText);
      if (lengthText != null &&
          (length == null || length < 0 || length > maxFrameBytes)) {
        throw const FormatException('Invalid STOMP content-length');
      }
      final end = length == null
          ? _buffer.indexOf(0, bodyStart)
          : bodyStart + length;
      if (end < 0 || end >= _buffer.length) break;
      if (_buffer[end] != 0) {
        throw const FormatException('Missing STOMP terminator');
      }
      final body = utf8.decode(_buffer.sublist(bodyStart, end));
      frames.add(StompFrame(command, headers, body));
      _buffer.removeRange(0, end + 1);
    }
    return frames;
  }

  static String _unescape(String value) {
    final result = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      if (value[i] != r'\') {
        result.write(value[i]);
        continue;
      }
      if (++i >= value.length) {
        throw const FormatException('Invalid STOMP escape');
      }
      result.write(switch (value[i]) {
        'n' => '\n',
        'r' => '\r',
        'c' => ':',
        r'\' => r'\',
        _ => throw const FormatException('Invalid STOMP escape'),
      });
    }
    return result.toString();
  }
}

String encodeStomp(String command, Map<String, String> headers) {
  String encode(String value) {
    if (value.contains('\u0000')) throw const FormatException('Invalid header');
    if (command == 'CONNECT') {
      if (value.contains('\n') || value.contains('\r')) {
        throw const FormatException('Invalid CONNECT header');
      }
      return value;
    }
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll(':', r'\c');
  }

  return '$command\n${headers.entries.map((e) => '${encode(e.key)}:${encode(e.value)}').join('\n')}\n\n\u0000';
}
