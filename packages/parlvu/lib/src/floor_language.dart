import 'models.dart';

class LanguageSwitch {
  const LanguageSwitch(this.wallClock, this.language);

  final DateTime wallClock;
  final AudioLanguage language;
}

final _wordTokens = RegExp(r"[\p{L}\p{N}']+", unicode: true);
final _markerText = RegExp(
  r'\[?speaking in (?:french|english)\]?|voice of interpretor|voice of interpreter|'
  r'\[?end of interpretation\]?|voix de l.interpr[eè]te|>>',
  caseSensitive: false,
);

List<String> _words(String value) => _wordTokens
    .allMatches(value.toLowerCase().replaceAll(_markerText, ' '))
    .map((m) => m.group(0)!)
    .toList();

List<LanguageSwitch> floorLanguageSwitches(
  List<SpeakerMark> marks,
  Map<AudioLanguage, List<Caption>> captions,
) {
  // Caption word streams, built once: a sitting has thousands of captions.
  final wordStreams = {
    for (final entry in captions.entries)
      entry.key: [
        for (final caption in entry.value)
          for (final word in _words(caption.text))
            (word: word, time: caption.begin),
      ],
  };
  final result = <LanguageSwitch>[];
  AudioLanguage? current;
  DateTime? lastTime;

  for (var m = 0; m < marks.length; m++) {
    final mark = marks[m];
    final paragraphs = mark.speech.paragraphs;
    if (paragraphs.isEmpty) continue;
    final nextMark = m + 1 < marks.length ? marks[m + 1].wallClock : null;
    final span =
        nextMark?.difference(mark.wallClock) ?? const Duration(seconds: 60);
    final paraWords = <List<String>>[];
    var inherited = current;
    for (final paragraph in paragraphs) {
      inherited = paragraph.language ?? inherited;
      final text = inherited == AudioLanguage.french
          ? paragraph.textFr
          : inherited == AudioLanguage.english
          ? paragraph.textEn
          : '';
      paraWords.add(_words(text));
    }
    final totalWords = paraWords.fold<int>(
      0,
      (sum, words) => sum + words.length,
    );

    for (var p = 0; p < paragraphs.length; p++) {
      final paragraph = paragraphs[p];
      final language = paragraph.language ?? current;
      if (language == null) continue;
      if (current == null) {
        current = language;
        lastTime = mark.wallClock;
        result.add(LanguageSwitch(lastTime, current));
        continue;
      }
      if (language == current) continue;

      final anchor = p == 0 || totalWords == 0
          ? mark.wallClock
          : mark.wallClock.add(
              Duration(
                microseconds:
                    (span.inMicroseconds *
                            paraWords
                                .take(p)
                                .fold<int>(
                                  0,
                                  (sum, words) => sum + words.length,
                                ) /
                            totalWords)
                        .round(),
              ),
            );
      final lowerBase = p == 0
          ? mark.wallClock.subtract(const Duration(seconds: 60))
          : mark.wallClock;
      final lower = lastTime != null && lastTime.isAfter(lowerBase)
          ? lastTime
          : lowerBase;
      final upper =
          nextMark?.add(const Duration(seconds: 30)) ??
          mark.wallClock.add(const Duration(minutes: 10));
      final candidates = <DateTime>[
        ..._textCandidates(
          paragraph,
          language,
          wordStreams[language] ?? const [],
          lower,
          upper,
        ),
        ..._markerCandidates(current, language, captions, lower, upper),
      ];
      candidates.sort((a, b) {
        final distance = a
            .difference(anchor)
            .abs()
            .compareTo(b.difference(anchor).abs());
        return distance != 0 ? distance : a.compareTo(b);
      });
      var time = candidates.isEmpty ? anchor : candidates.first;
      if (lastTime != null && time.isBefore(lastTime)) time = lastTime;
      if (result.isEmpty || result.last.language != language) {
        result.add(LanguageSwitch(time, language));
        current = language;
        lastTime = time;
      }
    }
  }
  result.sort((a, b) => a.wallClock.compareTo(b.wallClock));
  return [
    for (var i = 0; i < result.length; i++)
      if (i == 0 || result[i - 1].language != result[i].language) result[i],
  ];
}

List<DateTime> _textCandidates(
  SpeechParagraph paragraph,
  AudioLanguage language,
  List<({String word, DateTime time})> words,
  DateTime lower,
  DateTime upper,
) {
  final text = language == AudioLanguage.french
      ? paragraph.textFr
      : paragraph.textEn;
  final key = _words(text);
  if (key.length < 8) return [];
  final candidates = <DateTime>[];
  for (var p = 0; p < words.length; p++) {
    final time = words[p].time;
    if (time.isBefore(lower) || time.isAfter(upper)) continue;
    var score = 0;
    for (var i = 0; i < 8 && p + i < words.length; i++) {
      if (key[i] == words[p + i].word) score++;
    }
    if (score >= 5) candidates.add(time);
  }
  return candidates;
}

List<DateTime> _markerCandidates(
  AudioLanguage oldLanguage,
  AudioLanguage newLanguage,
  Map<AudioLanguage, List<Caption>> captions,
  DateTime lower,
  DateTime upper,
) {
  final result = <DateTime>[];
  void scan(AudioLanguage track, bool Function(String) matches) {
    for (final caption in captions[track] ?? const []) {
      if (caption.begin.isBefore(lower) || caption.begin.isAfter(upper)) {
        continue;
      }
      if (matches(caption.text.toLowerCase())) result.add(caption.begin);
    }
  }

  if (oldLanguage == AudioLanguage.english &&
      newLanguage == AudioLanguage.french) {
    scan(
      AudioLanguage.english,
      (text) =>
          text.contains('speaking in french') ||
          text.contains('voice of interpretor') ||
          text.contains('voice of interpreter'),
    );
  } else if (oldLanguage == AudioLanguage.french &&
      newLanguage == AudioLanguage.english) {
    scan(
      AudioLanguage.english,
      (text) => text.contains('end of interpretation'),
    );
    scan(
      AudioLanguage.french,
      (text) =>
          text.contains('voix de l’interpr') ||
          text.contains("voix de l'interpr"),
    );
  }
  return result;
}

AudioLanguage? floorLanguageAt(
  List<LanguageSwitch> switches,
  DateTime wallClock,
) {
  var low = 0;
  var high = switches.length;
  while (low < high) {
    final mid = low + (high - low) ~/ 2;
    if (switches[mid].wallClock.isAfter(wallClock)) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }
  return low == 0 ? null : switches[low - 1].language;
}
