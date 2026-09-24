import 'models.dart';

final _tokens = RegExp(r"[a-z0-9']+");
final _removePhrases = RegExp(
  r'voice of interpreter|voice of interpretor|speaking in french|speaking in english',
);

List<String> _normalise(String text) => _tokens
    .allMatches(text.toLowerCase().replaceAllMapped(_removePhrases, (_) => ' '))
    .map((m) => m.group(0)!)
    .toList();

List<SpeakerMark> alignSpeeches(List<Speech> speeches, List<Caption> captions) {
  if (speeches.isEmpty) return [];
  final speechTokens = speeches.map((s) => _normalise(s.textEn)).toList();
  final words = <({String word, DateTime time})>[];
  for (final caption in captions) {
    for (final word in _normalise(caption.text)) {
      words.add((word: word, time: caption.begin));
    }
  }
  final matched = List<DateTime?>.filled(speeches.length, null);
  DateTime? lastMatch;
  for (var s = 0; s < speeches.length; s++) {
    final keyTokens = speechTokens[s];
    if (keyTokens.length < 8) continue;
    final key = keyTokens.take(8).toList();
    final bucket = speeches[s].bucketTime;
    final lower = bucket.subtract(const Duration(seconds: 60));
    final upper = bucket.add(const Duration(minutes: 7));
    var bestScore = -1;
    var bestTime = DateTime.utc(9999);
    for (var p = 0; p < words.length; p++) {
      final time = words[p].time;
      if (time.isBefore(lower) ||
          time.isAfter(upper) ||
          (lastMatch != null && time.isBefore(lastMatch))) {
        continue;
      }
      var score = 0;
      for (var i = 0; i < 8 && p + i < words.length; i++) {
        if (key[i] == words[p + i].word) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        bestTime = time;
      }
    }
    if (bestScore >= 5) {
      matched[s] = bestTime;
      lastMatch = bestTime;
    }
  }
  final marks = <SpeakerMark>[];
  DateTime? prev;
  for (var i = 0; i < speeches.length; i++) {
    DateTime time;
    var source = MarkSource.captionMatch;
    if (matched[i] != null) {
      time = matched[i]!;
    } else {
      source = MarkSource.interpolated;
      final bucket = speeches[i].bucketTime;
      var before = 0, total = 0;
      for (var j = 0; j < speeches.length; j++) {
        if (speeches[j].bucketTime == bucket) {
          total += speechTokens[j].length;
          if (j < i) before += speechTokens[j].length;
        }
      }
      final micros = total == 0
          ? 0
          : (const Duration(minutes: 5).inMicroseconds * before / total)
                .round();
      time = bucket.add(Duration(microseconds: micros));
      for (var j = i + 1; j < speeches.length; j++) {
        if (matched[j] != null) {
          if (time.isAfter(matched[j]!)) time = matched[j]!;
          break;
        }
      }
    }
    if (prev != null && time.isBefore(prev)) {
      time = prev;
    }
    marks.add(
      SpeakerMark(speech: speeches[i], wallClock: time, source: source),
    );
    prev = time;
  }
  return marks;
}
