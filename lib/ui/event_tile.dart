import 'package:flutter/material.dart';
import 'package:parlvu/parlvu.dart';

import '../core/library.dart';

/// One row of an event listing: title, time, status chip, follow toggle and
/// an optional watch-progress bar.
class EventTile extends StatelessWidget {
  const EventTile({
    super.key,
    required this.event,
    required this.followed,
    required this.onTap,
    required this.onToggleFollow,
    this.progress,
  });

  final ListingEvent event;
  final bool followed;
  final VoidCallback onTap;
  final VoidCallback onToggleFollow;

  /// The viewer's progress in this event, if any.
  final WatchRecord? progress;

  static const Map<EventStatus, String> _chipText = {
    EventStatus.live: 'LIVE',
    EventStatus.paused: 'Paused',
    EventStatus.notStarted: 'Upcoming',
    EventStatus.cancelled: 'Cancelled',
    EventStatus.inCamera: 'In camera',
    EventStatus.opened: 'Opened',
  };

  String? get _chipLabel {
    if (event.status == EventStatus.ended) return null;
    return _chipText[event.status] ?? event.statusText;
  }

  static String _hhmm(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get _timeLabel {
    final start = event.actualStart ?? event.scheduledStart;
    final end = event.actualEnd ?? event.scheduledEnd;
    final s = _hhmm(start);
    return end == null ? s : '$s - ${_hhmm(end)}';
  }

  bool get _tappable =>
      event.status != EventStatus.cancelled &&
      event.status != EventStatus.inCamera;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = _chipLabel;
    final record = progress;
    final showProgress =
        record != null && !record.finished && record.duration != null;

    return ListTile(
      onTap: _tappable ? onTap : null,
      title: Row(
        children: [
          Expanded(child: Text(event.title, overflow: TextOverflow.ellipsis)),
          if (chip != null) ...[
            const SizedBox(width: 8),
            Chip(
              label: Text(chip),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_timeLabel, style: theme.textTheme.bodySmall),
          if (!event.isChamber)
            Text(event.location, style: theme.textTheme.bodySmall),
          if (showProgress)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
                value:
                    (record.position.inMilliseconds /
                            record.duration!.inMilliseconds)
                        .clamp(0.0, 1.0),
              ),
            ),
        ],
      ),
      trailing: IconButton(
        tooltip: followed ? 'Unfollow' : 'Follow',
        icon: Icon(followed ? Icons.star : Icons.star_border),
        onPressed: onToggleFollow,
      ),
    );
  }
}
