import 'package:parlvu/parlvu.dart';

/// What the player needs to open an event. Screens never import the player;
/// the app shell receives an [OpenEvent] callback from main.dart.
class OpenRequest {
  const OpenRequest({
    required this.eventId,
    required this.title,
    required this.eventDate,
    this.event,
    this.resumeAt,
    this.seekTo,
  });

  final int eventId;
  final String title;

  /// Ottawa calendar date, UTC midnight (see `parliamentDate`).
  final DateTime eventDate;

  /// The listing row when the caller has it (not from Continue watching).
  final ListingEvent? event;

  /// Where to resume, from the watch record; null plays from the start (or
  /// the live edge).
  final Duration? resumeAt;

  /// The wall-clock moment to play from (a feed item's video), 5 s early.
  /// Ignored on a live stream, which opens at the live edge.
  final DateTime? seekTo;
}

typedef OpenEvent = void Function(OpenRequest request);
