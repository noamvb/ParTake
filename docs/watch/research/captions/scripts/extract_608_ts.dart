import 'dart:io';
import 'dart:typed_data';

// Import the existing CEA-608 decoder from parlvu package
import '../../../../../packages/parlvu/lib/src/cea608.dart';

void main(List<String> args) async {
  final decoder = Cea608Decoder();
  final builder = BytesBuilder(copy: false);

  // Read chunks from stdin
  await for (final chunk in stdin) {
    builder.add(chunk);
    // Process when we have at least 188 * 100 bytes (18.8 KB)
    if (builder.length >= 188 * 100) {
      final bytes = builder.takeBytes();
      // Keep any trailing bytes not aligned to 188 bytes
      final alignedLen = (bytes.length ~/ 188) * 188;
      final toProcess = Uint8List.sublistView(bytes, 0, alignedLen);
      if (alignedLen < bytes.length) {
        builder.add(Uint8List.sublistView(bytes, alignedLen));
      }

      final changes = decodeCaptions(toProcess, decoder: decoder);
      for (final change in changes) {
        if (change.text != null && change.text!.trim().isNotEmpty) {
          final ptsSec = change.pts / 90000.0;
          print('[${ptsSec.toStringAsFixed(3)}] ${change.text!.replaceAll('\n', ' ')}');
        }
      }
    }
  }

  // Flush remaining
  if (builder.isNotEmpty) {
    final bytes = builder.takeBytes();
    final changes = decodeCaptions(bytes, decoder: decoder);
    for (final change in changes) {
      if (change.text != null && change.text!.trim().isNotEmpty) {
        final ptsSec = change.pts / 90000.0;
        print('[${ptsSec.toStringAsFixed(3)}] ${change.text!.replaceAll('\n', ' ')}');
      }
    }
  }
}
