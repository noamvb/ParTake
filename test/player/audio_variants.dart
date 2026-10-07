import 'package:parlvu/parlvu.dart';

EventDetail audioVideoDetail({
  int id = 45750,
  bool audio = true,
}) => EventDetail(
  id: id,
  recordingStart: DateTime.utc(2026, 9, 23),
  streams: [
    for (final language in AudioLanguage.values) ...[
      // SD comes first so a first-match implementation selects the wrong video.
      for (final variant in ['sd', 'video', if (audio) 'audio'])
        StreamVariant(
          language: language,
          url: Uri.parse(
            'https://example.test/$id/${language.name}/$variant.m3u8',
          ),
          tag: variant,
          audioOnly: variant == 'audio',
          isLive: false,
          isSd: variant == 'sd',
          preRoll: Duration.zero,
          duration: const Duration(minutes: 30),
          enableCc: false,
        ),
    ],
  ],
  captions: {},
);
