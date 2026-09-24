import 'dart:typed_data';

/// One CEA-608 byte pair carried in an ATSC A/53 caption triplet.
class CcPair {
  const CcPair(this.pts, this.field, this.b1, this.b2);

  final int pts;
  final int field;
  final int b1;
  final int b2;
}

/// Extracts valid CEA-608 pairs from MPEG-TS packets containing H.264 video.
/// Pairs are ordered by PTS, preserving their order within each access unit.
List<CcPair> extractCcPairs(Uint8List ts) {
  final tables = <int, List<int>>{};
  final pesByPid = <int, List<int>>{};
  final found = <({CcPair pair, int order})>[];
  var videoPid = -1;
  var order = 0;

  for (var offset = 0; offset + 188 <= ts.length; offset += 188) {
    if (ts[offset] != 0x47) continue;
    final b1 = ts[offset + 1], b2 = ts[offset + 2], b3 = ts[offset + 3];
    if ((b1 & 0x80) != 0 || ((b3 >> 4) & 1) == 0) continue;
    final pid = ((b1 & 0x1f) << 8) | b2;
    final start = (b1 & 0x40) != 0;
    final adaptationControl = (b3 >> 4) & 3;
    var cursor = offset + 4;
    if (adaptationControl == 2 || adaptationControl == 3) {
      cursor += 1 + ts[cursor];
    }
    if (adaptationControl == 2 || cursor >= offset + 188) continue;
    final payload = ts.sublist(cursor, offset + 188);
    if (pid == 0 || (videoPid < 0 && pid != 0x1fff)) {
      if (start) {
        final pointer = payload.isNotEmpty ? payload[0] : 0;
        final sectionOffset = 1 + pointer;
        if (sectionOffset < payload.length) {
          tables[pid] = <int>[...payload.sublist(sectionOffset)];
        }
      } else {
        tables.putIfAbsent(pid, () => <int>[]).addAll(payload);
      }
      if (pid == 0) {
        final pat = _section(tables[pid]!);
        if (pat != null && pat.length >= 12 && pat[0] == 0x00) {
          final end = pat.length - 4;
          for (var i = 8; i + 4 <= end; i += 4) {
            final program = (pat[i] << 8) | pat[i + 1];
            if (program != 0) {
              final pmtPid = ((pat[i + 2] & 0x1f) << 8) | pat[i + 3];
              tables.putIfAbsent(pmtPid, () => <int>[]);
            }
          }
        }
      }
      for (final entry in tables.entries.toList()) {
        final section = _section(entry.value);
        if (section == null || section.isEmpty || section[0] != 0x02) continue;
        final infoLength = ((section[10] & 0x0f) << 8) | section[11];
        var i = 12 + infoLength;
        final end = section.length - 4;
        while (i + 5 <= end) {
          final streamType = section[i];
          final elementaryPid = ((section[i + 1] & 0x1f) << 8) | section[i + 2];
          final esInfoLength = ((section[i + 3] & 0x0f) << 8) | section[i + 4];
          if (streamType == 0x1b) videoPid = elementaryPid;
          i += 5 + esInfoLength;
        }
      }
    }
    if (pid != videoPid) continue;
    if (start) {
      final previous = pesByPid.remove(pid);
      if (previous != null) _readPes(previous, found, () => order++);
      pesByPid[pid] = <int>[...payload];
    } else {
      pesByPid.putIfAbsent(pid, () => <int>[]).addAll(payload);
    }
  }
  for (final pes in pesByPid.values) {
    _readPes(pes, found, () => order++);
  }
  found.sort((a, b) {
    final pts = a.pair.pts.compareTo(b.pair.pts);
    return pts != 0 ? pts : a.order.compareTo(b.order);
  });
  return found.map((item) => item.pair).toList(growable: false);
}

List<int>? _section(List<int> bytes) {
  if (bytes.length < 3) return null;
  final size = ((bytes[1] & 0x0f) << 8) | bytes[2];
  final total = 3 + size;
  return bytes.length >= total ? bytes.sublist(0, total) : null;
}

void _readPes(
  List<int> bytes,
  List<({CcPair pair, int order})> found,
  int Function() nextOrder,
) {
  if (bytes.length < 9 || bytes[0] != 0 || bytes[1] != 0 || bytes[2] != 1) {
    return;
  }
  final flags = (bytes[7] >> 6) & 3;
  var pts = 0;
  if ((flags & 2) != 0 && bytes.length >= 14) {
    pts =
        ((bytes[9] & 0x0e) << 29) |
        (bytes[10] << 22) |
        ((bytes[11] & 0xfe) << 14) |
        (bytes[12] << 7) |
        ((bytes[13] & 0xfe) >> 1);
  }
  final payloadStart = 9 + bytes[8];
  if (payloadStart >= bytes.length) return;
  final stream = bytes.sublist(payloadStart);
  for (final nal in _annexBNals(stream)) {
    if (nal.isEmpty || (nal[0] & 0x1f) != 6) continue;
    final rbsp = <int>[];
    for (var i = 1; i < nal.length; i++) {
      if (i + 2 < nal.length &&
          nal[i] == 0 &&
          nal[i + 1] == 0 &&
          nal[i + 2] == 3) {
        rbsp.add(0);
        rbsp.add(0);
        i += 2;
      } else {
        rbsp.add(nal[i]);
      }
    }
    var i = 0;
    while (i < rbsp.length) {
      var payloadType = 0;
      while (i < rbsp.length && rbsp[i] == 0xff) {
        payloadType += 255;
        i++;
      }
      if (i >= rbsp.length) break;
      payloadType += rbsp[i++];
      var size = 0;
      while (i < rbsp.length && rbsp[i] == 0xff) {
        size += 255;
        i++;
      }
      if (i >= rbsp.length) break;
      size += rbsp[i++];
      if (size < 0 || i + size > rbsp.length) break;
      if (payloadType == 4) {
        _readT35(rbsp.sublist(i, i + size), pts, found, nextOrder);
      }
      i += size;
      if (payloadType == 0x80) break;
    }
  }
}

List<List<int>> _annexBNals(List<int> bytes) {
  final starts = <(int, int)>[];
  for (var i = 0; i + 3 <= bytes.length;) {
    if (bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 1) {
      starts.add((i, 3));
      i += 3;
    } else if (i + 4 <= bytes.length &&
        bytes[i] == 0 &&
        bytes[i + 1] == 0 &&
        bytes[i + 2] == 0 &&
        bytes[i + 3] == 1) {
      starts.add((i, 4));
      i += 4;
    } else {
      i++;
    }
  }
  return [
    for (var i = 0; i < starts.length; i++)
      bytes.sublist(
        starts[i].$1 + starts[i].$2,
        i + 1 < starts.length ? starts[i + 1].$1 : bytes.length,
      ),
  ];
}

void _readT35(
  List<int> data,
  int pts,
  List<({CcPair pair, int order})> found,
  int Function() nextOrder,
) {
  if (data.length < 7 ||
      data[0] != 0xb5 ||
      data[1] != 0 ||
      data[2] != 0x31 ||
      data[3] != 0x47 ||
      data[4] != 0x41 ||
      data[5] != 0x39 ||
      data[6] != 0x34 ||
      data.length < 10 ||
      data[7] != 3) {
    return;
  }
  final flags = data[8];
  if ((flags & 0x40) == 0) return;
  final count = flags & 0x1f;
  var index = 10;
  for (var n = 0; n < count && index + 3 <= data.length; n++, index += 3) {
    final header = data[index];
    if ((header & 4) == 0) continue;
    final ccType = header & 3;
    if (ccType > 1) continue;
    found.add((
      pair: CcPair(pts, ccType, data[index + 1], data[index + 2]),
      order: nextOrder(),
    ));
  }
}

/// A change to the visible caption display.
class CaptionChange {
  const CaptionChange(this.pts, this.text);

  final int pts;
  final String? text;
}

/// Stateful CEA-608 decoder for CC1 (field 1).
class Cea608Decoder {
  List<List<String>> _displayed = _grid();
  List<List<String>> _nonDisplayed = _grid();
  int _row = 14;
  int _column = 0;
  int _rollRows = 0;
  String _mode = 'pop';
  bool _channel2 = false;
  bool _textMode = false;
  int? _lastControl1;
  int? _lastControl2;

  CaptionChange? push(int pts, int b1, int b2) {
    b1 &= 0x7f;
    b2 &= 0x7f;
    if (b1 == 0 && b2 == 0) return null;
    if ((b1 == 0x12 || b1 == 0x13) && b2 >= 0x20 && b2 <= 0x3f) {
      _lastControl1 = null;
      _lastControl2 = null;
      final before = _visibleText();
      if (!_channel2 && !_textMode) {
        _backspace();
        final chars = b1 == 0x12
            ? const [
                'Á',
                'É',
                'Ó',
                'Ú',
                'Ü',
                'ü',
                "'",
                '¡',
                '*',
                "'",
                '—',
                '©',
                '℠',
                '•',
                '“',
                '”',
                'À',
                'Â',
                'Ç',
                'È',
                'Ê',
                'Ë',
                'ë',
                'Î',
                'Ï',
                'ï',
                'Ô',
                'Ù',
                'ù',
                'Û',
                '«',
                '»',
              ]
            : const [
                'Ã',
                'ã',
                'Í',
                'Ì',
                'ì',
                'Ò',
                'ò',
                'Õ',
                'õ',
                '{',
                '}',
                '\\',
                '^',
                '_',
                '|',
                '~',
                'Ä',
                'ä',
                'Ö',
                'ö',
                'ß',
                '¥',
                '¤',
                '│',
                'Å',
                'å',
                'Ø',
                'ø',
                '┌',
                '┐',
                '└',
                '┘',
              ];
        _put(chars[b2 - 0x20]);
      }
      return _changeIfVisible(pts, before);
    }
    final control = ((b1 >= 0x10 && b1 <= 0x1f) && b2 >= 0x20 && b2 <= 0x7f);
    if (control) {
      if (_lastControl1 == b1 && _lastControl2 == b2) {
        _lastControl1 = null;
        _lastControl2 = null;
        return null;
      }
      _lastControl1 = b1;
      _lastControl2 = b2;
    } else {
      _lastControl1 = null;
      _lastControl2 = null;
    }
    final before = _visibleText();
    if (b1 >= 0x18 && b1 <= 0x1f) {
      _channel2 = true;
      return null;
    }
    if (b1 >= 0x10 && b1 <= 0x17 && b2 >= 0x20 && b2 <= 0x2f) {
      _channel2 = false;
      if ((b1 == 0x14 || b1 == 0x15) && b2 >= 0x20) _command(b2);
      if (b1 == 0x17 && b2 >= 0x21 && b2 <= 0x23) {
        _column = (_column + b2 - 0x20).clamp(0, 31);
      }
      return _changeIfVisible(pts, before);
    }
    if (b1 >= 0x10 && b1 <= 0x17 && b2 >= 0x40 && b2 <= 0x7f) {
      _channel2 = false;
      _setPac(b1, b2);
      return null;
    }
    if (_channel2) return null;
    if (b1 == 0x11 && b2 >= 0x20 && b2 <= 0x2f) {
      if (!_textMode) _put(' ');
      return _changeIfVisible(pts, before);
    }
    if (b1 == 0x11 && b2 >= 0x30 && b2 <= 0x3f) {
      if (!_textMode) {
        _put(
          const [
            '®',
            '°',
            '½',
            '¿',
            '™',
            '¢',
            '£',
            '♪',
            'à',
            ' ',
            'è',
            'â',
            'ê',
            'î',
            'ô',
            'û',
          ][b2 - 0x30],
        );
      }
      return _changeIfVisible(pts, before);
    }
    if ((b1 >= 0x20 && b1 <= 0x7f) || (b2 >= 0x20 && b2 <= 0x7f)) {
      if (!_textMode) {
        if (b1 >= 0x20 && b1 <= 0x7f) _put(_standardChar(b1));
        if (b2 >= 0x20 && b2 <= 0x7f) _put(_standardChar(b2));
      }
      return _changeIfVisible(pts, before);
    }
    return null;
  }

  void _command(int command) {
    switch (command) {
      case 0x20:
        _mode = 'pop';
        _rollRows = 0;
        _textMode = false;
        break;
      case 0x21:
        _backspace();
        break;
      case 0x24:
        for (var c = _column; c < 32; c++) {
          _active()[_row][c] = ' ';
        }
        break;
      case 0x25:
      case 0x26:
      case 0x27:
        _mode = 'roll';
        _rollRows = command - 0x23;
        _textMode = false;
        break;
      case 0x28:
        break;
      case 0x29:
        _mode = 'paint';
        _rollRows = 0;
        _textMode = false;
        break;
      case 0x2a:
      case 0x2b:
        _textMode = true;
        break;
      case 0x2c:
        _displayed = _grid();
        break;
      case 0x2d:
        _carriageReturn();
        break;
      case 0x2e:
        _nonDisplayed = _grid();
        break;
      case 0x2f:
        final old = _displayed;
        _displayed = _nonDisplayed;
        _nonDisplayed = old;
        _mode = 'pop';
        _rollRows = 0;
        _textMode = false;
        break;
    }
  }

  void _setPac(int b1, int b2) {
    const rows = [0, 11, 1, 2, 3, 4, 12, 13, 14, 15, 5, 6, 7, 8, 9, 10];
    final index = (b1 - 0x10) * 2 + ((b2 & 0x20) == 0 ? 0 : 1);
    if (index >= 0 && index < rows.length) _row = rows[index] - 1;
    final indent = (b2 & 0x10) != 0;
    _column = indent ? ((b2 & 0x0e) >> 1) * 4 : 0;
  }

  void _carriageReturn() {
    if (_mode != 'roll' || _rollRows == 0) return;
    final first = (_row - _rollRows + 1).clamp(0, 14);
    for (var r = first; r < _row; r++) {
      _displayed[r] = List<String>.from(_displayed[r + 1]);
    }
    _displayed[_row] = List<String>.filled(32, ' ');
    _column = 0;
  }

  List<List<String>> _active() => _mode == 'pop' ? _nonDisplayed : _displayed;

  void _put(String char) {
    if (_column < 32) _active()[_row][_column++] = char;
  }

  void _backspace() {
    if (_column > 0) {
      _column--;
      _active()[_row][_column] = ' ';
    }
  }

  String? _visibleText() {
    final lines = <String>[];
    for (final row in _displayed) {
      final text = row.join().trimRight();
      if (text.isNotEmpty) lines.add(text);
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  CaptionChange? _changeIfVisible(int pts, String? before) {
    final after = _visibleText();
    return before == after ? null : CaptionChange(pts, after);
  }
}

List<List<String>> _grid() => List.generate(15, (_) => List.filled(32, ' '));

String _standardChar(int code) {
  const replacements = {
    0x2a: 'á',
    0x5c: 'é',
    0x5e: 'í',
    0x5f: 'ó',
    0x60: 'ú',
    0x7b: 'ç',
    0x7c: '÷',
    0x7d: 'Ñ',
    0x7e: 'ñ',
    0x7f: '█',
  };
  return replacements[code] ?? String.fromCharCode(code == 0x27 ? 0x27 : code);
}

/// Decodes valid CC1 pairs from [ts], optionally using an existing decoder.
List<CaptionChange> decodeCaptions(Uint8List ts, {Cea608Decoder? decoder}) {
  final activeDecoder = decoder ?? Cea608Decoder();
  final changes = <CaptionChange>[];
  for (final pair in extractCcPairs(ts)) {
    if (pair.field != 0) continue;
    final change = activeDecoder.push(pair.pts, pair.b1, pair.b2);
    if (change != null) changes.add(change);
  }
  return changes;
}
