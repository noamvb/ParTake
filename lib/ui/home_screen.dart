import 'dart:async';

import 'package:flutter/material.dart';
import 'package:parlvu/parlvu.dart';

import '../core/library.dart';
import 'event_tile.dart';
import 'load_view.dart';
import 'open_request.dart';

/// The first screen: what's live now, then where the viewer left off, then
/// today's schedule.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.source,
    required this.library,
    required this.onOpen,
    required this.now,
  });

  final EventSource source;
  final Library library;
  final OpenEvent onOpen;
  final DateTime Function() now;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeData {
  const _HomeData({required this.liveNow, required this.today});

  final List<ListingEvent> liveNow;
  final List<ListingEvent> today;
}

class _HomeScreenState extends State<HomeScreen> {
  final _loadKey = GlobalKey<LoadViewState<_HomeData>>();
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<_HomeData> _load({bool refresh = false}) async {
    final live = await widget.source.liveNow(refresh: refresh);
    final today = await widget.source.day(
      parliamentDate(widget.now()),
      refresh: refresh,
    );
    final data = _HomeData(liveNow: live, today: today);
    _scheduleRefresh(data);
    return data;
  }

  static bool _active(ListingEvent e) =>
      e.status == EventStatus.live ||
      e.status == EventStatus.paused ||
      e.status == EventStatus.notStarted;

  bool _needsRefresh(_HomeData data) =>
      data.liveNow.any(_active) || data.today.any(_active);

  void _scheduleRefresh(_HomeData data) {
    _timer?.cancel();
    _timer = null;
    if (!_needsRefresh(data)) return;
    _timer = Timer(const Duration(seconds: 60), () {
      _loadKey.currentState?.reload(refresh: true);
    });
  }

  List<ListingEvent> _sortFollowedFirst(
    List<ListingEvent> events,
    Set<String> followed,
  ) {
    final followedList = <ListingEvent>[];
    final restList = <ListingEvent>[];
    for (final e in events) {
      (followed.contains(followKeyOf(e)) ? followedList : restList).add(e);
    }
    return [...followedList, ...restList];
  }

  static String _formatResume(Duration position) {
    final totalSeconds = position.inSeconds;
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:$ss';
    }
    return '$m:$ss';
  }

  EventTile _tileFor(ListingEvent e) {
    final key = followKeyOf(e);
    final followed = widget.library.follows.contains(key);
    return EventTile(
      event: e,
      followed: followed,
      onTap: () => widget.onOpen(
        OpenRequest(
          eventId: e.id,
          title: e.title,
          eventDate: parliamentDate(e.actualStart ?? e.scheduledStart),
          event: e,
          resumeAt: widget.library.record(e.id)?.position,
        ),
      ),
      onToggleFollow: () => widget.library.setFollowed(key, !followed),
      progress: widget.library.record(e.id),
    );
  }

  Widget _continueWatchingSection() {
    final records = widget.library.continueWatching;
    if (records.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Continue watching'),
        for (final r in records) _continueWatchingTile(r),
      ],
    );
  }

  Widget _continueWatchingTile(WatchRecord r) {
    final duration = r.duration;
    return ListTile(
      title: Text(r.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Resume at ${_formatResume(r.position)}'),
          if (duration != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
                value: (r.position.inMilliseconds / duration.inMilliseconds)
                    .clamp(0.0, 1.0),
              ),
            ),
        ],
      ),
      onTap: () => widget.onOpen(
        OpenRequest(
          eventId: r.eventId,
          title: r.title,
          eventDate: r.eventDate,
          resumeAt: r.position,
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, _HomeData data) {
    return ListenableBuilder(
      listenable: widget.library,
      builder: (context, _) {
        final followed = widget.library.follows;
        final today = _sortFollowedFirst(data.today, followed);

        return ListView(
          children: [
            if (data.liveNow.isNotEmpty) ...[
              const _SectionHeader('Live now'),
              for (final e in data.liveNow) _tileFor(e),
            ],
            _continueWatchingSection(),
            const _SectionHeader('Today'),
            if (today.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nothing scheduled today.'),
              )
            else
              for (final e in today) _tileFor(e),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LoadView<_HomeData>(
      key: _loadKey,
      loader: _load,
      builder: _buildContent,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}
