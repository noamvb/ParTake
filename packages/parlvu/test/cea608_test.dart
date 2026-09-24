import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:parlvu/parlvu.dart';
import 'package:test/test.dart';

void main() {
  final fixture = File('test/fixtures/live_cc_en_39007_39023.ts');

  test('extracts valid pairs from the live fixture in PTS order', () {
    final pairs = extractCcPairs(Uint8List.fromList(fixture.readAsBytesSync()));
    expect(pairs, isNotEmpty);
    expect(pairs.map((pair) => pair.pts), orderedEquals(pairs.map((pair) => pair.pts).toList()..sort()));
    expect(pairs.every((pair) => pair.field == 0 || pair.field == 1), isTrue);
    // Printed for the implementation report using the same assertion result.
    print('live fixture CC pair count: ${pairs.length}');
  });

  test('roll-up scrolls and limits the two-row window', () {
    final decoder = _Harness();
    var pts = 1;
    void push(int a, int b) => decoder.push(pts++, a, b);
    void text(String value) {
      for (var i = 0; i < value.length; i += 2) {
        push(value.codeUnitAt(i), i + 1 < value.length ? value.codeUnitAt(i + 1) : 0);
      }
    }

    push(0x14, 0x25); // RU2
    push(0x14, 0x2d); // CR
    text('HELLO');
    push(0x14, 0x2d);
    text('WORLD');
    expect(_visible(decoder), 'HELLO\nWORLD');
    push(0x14, 0x2d);
    text('AGAIN');
    expect(_visible(decoder), 'WORLD\nAGAIN');
  });

  test('pop-on reveals captions only at EOC and EDM clears them', () {
    final decoder = _Harness();
    expect(decoder.push(1, 0x14, 0x20), isNull); // RCL
    expect(decoder.push(2, 0x14, 0x60), isNull); // PAC row 15
    expect(decoder.push(3, 0x48, 0x49), isNull);
    expect(decoder.push(4, 0x14, 0x2f)?.text, 'HI'); // EOC
    expect(decoder.push(5, 0x14, 0x2c)?.text, isNull); // EDM
  });

  test('suppresses repeated control pairs without repeating their action', () {
    final decoder = _Harness();
    var pts = 1;
    void push(int a, int b) => decoder.push(pts++, a, b);
    push(0x14, 0x25);
    push(0x14, 0x25);
    push(0x41, 0);
    push(0x14, 0x2d);
    push(0x14, 0x2d);
    push(0x42, 0);
    expect(_visible(decoder), 'A\nB');
  });

  test('strips parity and decodes standard, special, and extended characters', () {
    String? decodePair(int a, int b, {bool highBits = false}) {
      final decoder = _Harness();
      decoder.push(1, 0x14, 0x29); // RDC
      decoder.push(2, highBits ? a | 0x80 : a, highBits ? b | 0x80 : b);
      return _visible(decoder);
    }

    expect(decodePair(0x48, 0x49), decodePair(0x48, 0x49, highBits: true));
    expect(decodePair(0x11, 0x37), '♪');
    expect(decodePair(0x2a, 0), 'á');
    final decoder = _Harness();
    decoder.push(1, 0x14, 0x29);
    decoder.push(2, 0x41, 0);
    decoder.push(3, 0x12, 0x21); // É replaces A
    expect(_visible(decoder), 'É');
  });

  test('channel 2 commands and text do not affect CC1', () {
    final decoder = _Harness();
    expect(decoder.push(1, 0x1c, 0x25), isNull);
    expect(decoder.push(2, 0x41, 0x42), isNull);
    expect(_visible(decoder), isNull);
  });

  test('decodes at least 60 hls.js reference lines from the live fixture', () {
    final bytes = Uint8List.fromList(fixture.readAsBytesSync());
    final changes = decodeCaptions(bytes);
    final displayed = changes.map((change) => change.text ?? '').join(' ');
    final normalizedDisplay = _normalize(displayed);
    final references = (jsonDecode(File('test/fixtures/live_cc_en_hlsjs_cues.json').readAsStringSync())
        as Map<String, dynamic>)['lines'] as List<dynamic>;
    final misses = <String>[];
    var matched = 0;
    for (final line in references.cast<String>()) {
      if (normalizedDisplay.contains(_normalize(line))) {
        matched++;
      } else {
        misses.add(line);
      }
    }
    print('hls.js reference lines matched: $matched/${references.length}');
    expect(matched, greaterThanOrEqualTo(60), reason: 'Examples not found: ${misses.take(10).join(' | ')}');
  });
}

class _Harness {
  final Cea608Decoder _decoder = Cea608Decoder();
  String? text;

  CaptionChange? push(int pts, int b1, int b2) {
    final change = _decoder.push(pts, b1, b2);
    if (change != null) text = change.text;
    return change;
  }
}

String? _visible(_Harness decoder) => decoder.text;

String _normalize(String value) => value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
