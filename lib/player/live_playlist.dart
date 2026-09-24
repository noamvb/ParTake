/// A live HLS media playlist re-served as a growing EVENT playlist.
///
/// ffmpeg's HLS demuxer (mpv on Android) marks a live playlist without
/// `#EXT-X-PLAYLIST-TYPE` unseekable and keeps only the few segments it has
/// buffered, so the ~13 h ParlVU DVR window is out of reach. An EVENT
/// playlist is seekable. This keeps every segment seen since the first
/// fetch, in media-sequence order, and never drops one, as EVENT requires.
class LivePlaylist {
  LivePlaylist();

  final List<LiveSegment> _segments = [];
  int? _firstSequence;
  int _targetDuration = 12;

  /// Wall clock of the first segment held (ParlVU's `#STARTTIME:`), or null
  /// when the playlist has none.
  DateTime? windowStart;

  /// Number of segments held.
  int get length => _segments.length;

  /// Media time of the newest segment's end: the live edge, measured from
  /// the first segment held.
  Duration get edge =>
      _segments.fold(Duration.zero, (sum, s) => sum + s.duration);

  /// Whether [text] is a live media playlist: segments, no end, no type.
  static bool isLiveMedia(String text) =>
      text.contains('#EXTINF') &&
      !text.contains('#EXT-X-ENDLIST') &&
      !text.contains('#EXT-X-PLAYLIST-TYPE');

  /// First variant URI of a master playlist, resolved against [base], or
  /// null when [text] is not a master playlist.
  static Uri? firstVariant(String text, Uri base) {
    final lines = text.split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
      for (var j = i + 1; j < lines.length; j++) {
        final uri = lines[j].trim();
        if (uri.isEmpty || uri.startsWith('#')) continue;
        return base.resolve(uri);
      }
    }
    return null;
  }

  /// Adds the segments of upstream playlist [text] (fetched from [base])
  /// that are newer than those held.
  void merge(String text, Uri base) {
    int? sequence;
    Duration? pending;
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#STARTTIME:') && _segments.isEmpty) {
        windowStart = DateTime.tryParse(line.substring(11).trim());
      } else if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        sequence = int.tryParse(line.substring(22).trim());
      } else if (line.startsWith('#EXT-X-TARGETDURATION:')) {
        _targetDuration =
            int.tryParse(line.substring(22).trim()) ?? _targetDuration;
      } else if (line.startsWith('#EXTINF:')) {
        final seconds = double.tryParse(line.substring(8).split(',').first);
        if (seconds != null) {
          pending = Duration(microseconds: (seconds * 1e6).round());
        }
      } else if (!line.startsWith('#') && pending != null) {
        final number = sequence ?? 0;
        sequence = number + 1;
        _firstSequence ??= number;
        final next = _firstSequence! + _segments.length;
        if (number == next) {
          _segments.add(LiveSegment(number, pending, base.resolve(line)));
        }
        pending = null;
      }
    }
  }

  /// The EVENT playlist ffmpeg reloads while playing.
  String render() {
    final out = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-VERSION:3')
      ..writeln('#EXT-X-PLAYLIST-TYPE:EVENT')
      ..writeln('#EXT-X-TARGETDURATION:$_targetDuration')
      ..writeln('#EXT-X-MEDIA-SEQUENCE:${_firstSequence ?? 0}');
    for (final s in _segments) {
      final seconds = s.duration.inMicroseconds / 1e6;
      out
        ..writeln('#EXTINF:${seconds.toStringAsFixed(3)},')
        ..writeln(s.uri);
    }
    return out.toString();
  }
}

class LiveSegment {
  const LiveSegment(this.sequence, this.duration, this.uri);
  final int sequence;
  final Duration duration;
  final Uri uri;
}
