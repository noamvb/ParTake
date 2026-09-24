import 'package:flutter/material.dart';
import 'package:parlvu/parlvu.dart';

import '../core/library.dart';
import 'event_tile.dart';
import 'load_view.dart';
import 'open_request.dart';

enum _Filter { all, chamber, committees, following }

String _filterLabel(_Filter f) => switch (f) {
  _Filter.all => 'All',
  _Filter.chamber => 'Chamber',
  _Filter.committees => 'Committees',
  _Filter.following => 'Following',
};

/// Day-by-day browser: pick a date, see everything ParlVU scheduled for it.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({
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
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  late DateTime _date;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _date = parliamentDate(widget.now());
  }

  Future<List<ListingEvent>> _load({bool refresh = false}) =>
      widget.source.day(_date, refresh: refresh);

  void _changeDay(int deltaDays) {
    setState(() => _date = _date.add(Duration(days: deltaDays)));
  }

  Future<void> _pickDate() async {
    final today = parliamentDate(widget.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.utc(2004, 2, 2),
      lastDate: today.add(const Duration(days: 14)),
    );
    if (picked != null) {
      setState(
        () => _date = DateTime.utc(picked.year, picked.month, picked.day),
      );
    }
  }

  List<ListingEvent> _applyFilter(List<ListingEvent> events) {
    switch (_filter) {
      case _Filter.all:
        return events;
      case _Filter.chamber:
        return events.where((e) => e.isChamber).toList();
      case _Filter.committees:
        return events.where((e) => !e.isChamber).toList();
      case _Filter.following:
        final followed = widget.library.follows;
        return events.where((e) => followed.contains(followKeyOf(e))).toList();
    }
  }

  static String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous day',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _changeDay(-1),
            ),
            Expanded(
              child: TextButton(
                onPressed: _pickDate,
                child: Text(_formatDate(_date)),
              ),
            ),
            IconButton(
              tooltip: 'Next day',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _changeDay(1),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 8,
            children: [
              for (final f in _Filter.values)
                ChoiceChip(
                  label: Text(_filterLabel(f)),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
            ],
          ),
        ),
        Expanded(
          child: LoadView<List<ListingEvent>>(
            key: ValueKey(_date),
            loader: _load,
            builder: (context, events) => ListenableBuilder(
              listenable: widget.library,
              builder: (context, _) {
                final filtered = _applyFilter(events);
                if (filtered.isEmpty) {
                  return const Center(
                    child: Text('No proceedings on this day.'),
                  );
                }
                final followed = widget.library.follows;
                return ListView(
                  children: [
                    for (final e in filtered)
                      EventTile(
                        event: e,
                        followed: followed.contains(followKeyOf(e)),
                        onTap: () => widget.onOpen(
                          OpenRequest(
                            eventId: e.id,
                            title: e.title,
                            eventDate: parliamentDate(
                              e.actualStart ?? e.scheduledStart,
                            ),
                            event: e,
                            resumeAt: widget.library.record(e.id)?.position,
                          ),
                        ),
                        onToggleFollow: () => widget.library.setFollowed(
                          followKeyOf(e),
                          !followed.contains(followKeyOf(e)),
                        ),
                        progress: widget.library.record(e.id),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
