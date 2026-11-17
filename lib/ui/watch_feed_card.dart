part of 'watch_screen.dart';

class _FeedCard extends StatelessWidget {
  const _FeedCard({
    required this.item,
    required this.follows,
    required this.now,
    required this.expanded,
    required this.onToggle,
    required this.onWatch,
    required this.onOpen,
  });

  final WatchFeedItem item;
  final List<WatchFollow> follows;
  final DateTime now;
  final bool expanded;
  final VoidCallback onToggle;
  final OpenEvent onWatch;
  final void Function(String url) onOpen;

  static IconData _icon(String kind) => switch (kind) {
    'speech' => Icons.record_voice_over,
    'division' => Icons.how_to_vote,
    'bill_stage' => Icons.gavel,
    _ => Icons.article,
  };

  static String _when(DateTime at, DateTime now) {
    final local = at.toLocal();
    final clock =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    final today = now.toLocal();
    if (local.year == today.year &&
        local.month == today.month &&
        local.day == today.day) {
      return 'Today, $clock';
    }
    return '${_weekdays[local.weekday - 1]} ${local.day} '
        '${_months[local.month - 1]}, $clock';
  }

  static String _result(String result) => switch (result) {
    'agreed' => 'Agreed to',
    'negatived' => 'Negatived',
    'tie' => 'Tie',
    _ => result,
  };

  static String _vote(String vote) => switch (vote) {
    'yea' => 'Yea',
    'nay' => 'Nay',
    'paired' => 'Paired',
    _ => vote,
  };

  String _mpLabel(String personId) {
    for (final follow in follows) {
      if (follow.kind == 'mp' && follow.mp?.personId == personId) {
        return follow.label;
      }
    }
    return personId;
  }

  WatchFollow? _followById(String id) {
    for (final follow in follows) {
      if (follow.id == id) return follow;
    }
    return null;
  }

  List<String> _matchedLabels() {
    final labels = <String>[];
    for (final match in item.follows) {
      final follow = _followById(match.id);
      if (follow == null) continue;
      final percent = follow.kind == 'topic' && match.score < 1;
      labels.add(
        percent
            ? '${follow.label} ${(match.score * 100).round()}%'
            : follow.label,
      );
    }
    return labels;
  }

  static String _speakerLine(String name, WatchSpeaker speaker) =>
      speaker.party == null ? name : '$name · ${speaker.party}';

  List<Widget> _divisionLines(ThemeData theme, WatchDivision division) => [
    Text(
      '${_result(division.result)} · ${division.yeas} yea, '
      '${division.nays} nay, ${division.paired} paired',
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    for (final party in division.parties)
      if (party.split)
        Text(
          '${party.party} split: ${party.yea} yea, ${party.nay} nay',
          style: theme.textTheme.bodySmall,
        ),
    for (final mp in division.mps)
      Text(
        '${_mpLabel(mp.personId)}: ${_vote(mp.vote)}',
        style: theme.textTheme.bodySmall,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final speaker = item.speaker;
    final division = item.division;
    final video = item.video;
    final matched = _matchedLabels();
    final links = item.links;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_icon(item.kind), size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _when(item.at, now),
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (item.source == 'captions')
                Text(
                  'From live captions',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              if (item.kind == 'speech' && speaker != null)
                Text(
                  speaker.from == 'caption_call'
                      ? _speakerLine('Probably ${speaker.name}', speaker)
                      : _speakerLine(speaker.name, speaker),
                  style: theme.textTheme.bodyMedium,
                ),
              const SizedBox(height: 4),
              Text(
                item.text,
                maxLines: expanded ? null : 4,
                overflow: TextOverflow.ellipsis,
              ),
              if (division != null) ..._divisionLines(theme, division),
              if (matched.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final label in matched)
                        Chip(
                          label: Text(label),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
              Wrap(
                children: [
                  if (video != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => onWatch(
                        OpenRequest(
                          eventId: int.parse(video.event),
                          title: item.title,
                          eventDate: parliamentDate(video.at),
                          seekTo: video.at,
                        ),
                      ),
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Watch'),
                    ),
                  if (links.hansard != null)
                    TextButton(
                      onPressed: () => onOpen(links.hansard!),
                      child: Text(
                        item.source == 'evidence' ? 'Evidence' : 'Hansard',
                      ),
                    ),
                  if (links.legisinfo != null)
                    TextButton(
                      onPressed: () => onOpen(links.legisinfo!),
                      child: const Text('LEGISinfo'),
                    ),
                  if (links.division != null)
                    TextButton(
                      onPressed: () => onOpen(links.division!),
                      child: const Text('Vote details'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
