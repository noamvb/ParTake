import 'package:flutter/material.dart';
import 'package:parlvu/parlvu.dart';

import '../calendar/sitting_calendar.dart';
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

/// Month calendar and the ParlVU schedule for the selected Ottawa day.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({
    super.key,
    required this.source,
    required this.library,
    required this.onOpen,
    required this.now,
    this.showFollow = true,
    this.calendar,
  });

  final SittingCalendarClient? calendar;
  final bool showFollow;
  final EventSource source;
  final Library library;
  final OpenEvent onOpen;
  final DateTime Function() now;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  late DateTime _date;
  late DateTime _month;
  final _years = <int, Set<DateTime>>{};
  final _failedYears = <int>{};
  final _loadingYears = <int>{};
  final _followedDays = <DateTime>{};
  final _monthEvents = <(int, int), Future<List<ListingEvent>>>{};
  int _rangeGeneration = 0;
  String? _rangeKey;

  DateTime get _firstVisible {
    final first = DateTime.utc(_month.year, _month.month);
    return first.subtract(Duration(days: first.weekday - 1));
  }

  DateTime get _lastVisible => _firstVisible.add(const Duration(days: 41));
  DateTime get _today => parliamentDate(widget.now());
  DateTime get _lastMonth => DateTime.utc(_today.year + 1, 12);

  bool _known(DateTime day) => _years[day.year]?.isNotEmpty == true;
  bool _sits(DateTime day) => _years[day.year]?.contains(day) == true;

  Future<void> _loadYear(int year) async {
    final calendar = widget.calendar;
    if (calendar == null ||
        _loadingYears.contains(year) ||
        _years.containsKey(year)) {
      return;
    }
    _loadingYears.add(year);
    try {
      final days = await calendar.year(year);
      if (mounted && widget.calendar == calendar) {
        setState(() {
          _years[year] = days;
          _failedYears.remove(year);
        });
      }
    } catch (_) {
      if (mounted && widget.calendar == calendar) {
        setState(() => _failedYears.add(year));
      }
    } finally {
      _loadingYears.remove(year);
    }
  }

  void _loadMonth() {
    for (final year in {_firstVisible.year, _lastVisible.year}) {
      _loadYear(year);
    }
    _loadFollowed();
  }

  void _loadFollowed() {
    final follows = widget.library.follows.toList()..sort();
    final key =
        '${_month.year}-${_month.month}:${follows.join(',')}:${widget.showFollow}';
    if (key == _rangeKey) return;
    _rangeKey = key;
    final generation = ++_rangeGeneration;
    _followedDays.clear();
    if (!widget.showFollow ||
        follows.isEmpty ||
        _month.isAfter(_today.add(const Duration(days: 14)))) {
      return;
    }
    final monthKey = (_month.year, _month.month);
    final future = _monthEvents.putIfAbsent(
      monthKey,
      () => widget.source.range(_firstVisible, _lastVisible),
    );
    future.then(
      (events) {
        if (!mounted || generation != _rangeGeneration) return;
        setState(() {
          _followedDays.addAll(
            events
                .where((e) => follows.contains(followKeyOf(e)))
                .map((e) => parliamentDate(e.actualStart ?? e.scheduledStart)),
          );
        });
      },
      onError: (Object _) {
        _monthEvents.remove(monthKey);
      },
    );
  }

  void _libraryChanged() {
    setState(_loadFollowed);
  }

  @override
  void didUpdateWidget(BrowseScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.library != widget.library) {
      oldWidget.library.removeListener(_libraryChanged);
      widget.library.addListener(_libraryChanged);
      _rangeKey = null;
    }
    if (oldWidget.source != widget.source) {
      _monthEvents.clear();
      _rangeKey = null;
    }
    if (oldWidget.calendar != widget.calendar) {
      _years.clear();
      _failedYears.clear();
    }
    _loadMonth();
  }

  @override
  void dispose() {
    widget.library.removeListener(_libraryChanged);
    super.dispose();
  }

  void _selectDay(DateTime day) {
    setState(() {
      _date = day;
      final month = DateTime.utc(day.year, day.month);
      final firstMonth = DateTime.utc(2004, 2);
      _month = month.isBefore(firstMonth)
          ? firstMonth
          : month.isAfter(_lastMonth)
          ? _lastMonth
          : month;
      _loadMonth();
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime.utc(_month.year, _month.month + delta);
      _loadMonth();
    });
  }

  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _date = parliamentDate(widget.now());
    _month = DateTime.utc(_date.year, _date.month);
    widget.library.addListener(_libraryChanged);
    _loadMonth();
  }

  Future<List<ListingEvent>> _load({bool refresh = false}) =>
      widget.source.day(_date, refresh: refresh);

  void _changeDay(int deltaDays) {
    _selectDay(_date.add(Duration(days: deltaDays)));
  }

  Future<void> _pickDate() async {
    final today = parliamentDate(widget.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(DateTime.utc(2004, 2))
          ? DateTime.utc(2004, 2)
          : _date.isAfter(DateTime.utc(today.year + 1, 12, 31))
          ? DateTime.utc(today.year + 1, 12, 31)
          : _date,
      firstDate: DateTime.utc(2004, 2),
      lastDate: DateTime.utc(today.year + 1, 12, 31),
    );
    if (picked != null) {
      _selectDay(DateTime.utc(picked.year, picked.month, picked.day));
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

  bool _breakRow(DateTime monday) => List.generate(
    5,
    (i) => monday.add(Duration(days: i)),
  ).every((day) => _known(day) && !_sits(day));

  Widget _grid() {
    final colors = Theme.of(context).colorScheme;
    final first = _firstVisible;
    var previousBreak = false;
    final rows = <Widget>[];
    for (var row = 0; row < 6; row++) {
      final monday = first.add(Duration(days: row * 7));
      final breaking = _breakRow(monday);
      final inMonth = monday.month == _month.month;
      final caption = breaking && !previousBreak && inMonth;
      if (inMonth) previousBreak = breaking;
      rows.add(
        Column(
          children: [
            Row(
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: _dayCell(
                      monday.add(Duration(days: column)),
                      breaking && column < 5,
                    ),
                  ),
              ],
            ),
            SizedBox(
              height: 20,
              child: caption
                  ? const Text(
                      'House not sitting',
                      key: ValueKey('break-caption'),
                      style: TextStyle(fontSize: 12),
                    )
                  : null,
            ),
          ],
        ),
      );
    }
    final unavailable = {
      _firstVisible.year,
      _lastVisible.year,
    }.any(_failedYears.contains);
    return SizedBox(
      key: const ValueKey('month-grid'),
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                icon: const Icon(Icons.chevron_left),
                onPressed: _month.isAfter(DateTime.utc(2004, 2))
                    ? () => _changeMonth(-1)
                    : null,
              ),
              Expanded(
                child: Text(
                  '${calendarMonths[_month.month - 1]} ${_month.year}',
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                icon: const Icon(Icons.chevron_right),
                onPressed: _month.isBefore(_lastMonth)
                    ? () => _changeMonth(1)
                    : null,
              ),
              TextButton(
                onPressed: () => _selectDay(_today),
                child: const Text('Today'),
              ),
            ],
          ),
          Row(
            children: [
              for (final label in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(child: Center(child: Text(label))),
            ],
          ),
          ...rows,
          if (unavailable)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Sitting calendar unavailable',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                TextButton(onPressed: _loadMonth, child: const Text('Retry')),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime day, bool breaking) {
    final colors = Theme.of(context).colorScheme;
    final selected = day == _date;
    final followed = _followedDays.contains(day);
    final label =
        '${calendarWeekdays[day.weekday - 1]} ${day.day} ${calendarMonths[day.month - 1]}'
        '${_sits(day) ? ', sitting day' : ''}${followed ? ', followed' : ''}';
    return Semantics(
      label: label,
      onTap: () => _selectDay(day),
      button: true,
      selected: selected,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _selectDay(day),
        child: Container(
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: selected
                ? colors.primary
                : _sits(day)
                ? colors.secondaryContainer
                : null,
            border: day == _today ? Border.all(color: colors.primary) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: TextStyle(
                  color: selected
                      ? colors.onPrimary
                      : day.month != _month.month || breaking
                      ? colors.onSurfaceVariant
                      : colors.onSurface,
                ),
              ),
              SizedBox(
                height: 5,
                child: followed
                    ? Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: selected ? colors.onPrimary : colors.primary,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 840;
      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(child: _grid()),
            const SizedBox(width: 16),
            Expanded(child: _daySection(wide: true)),
          ],
        );
      }
      return SingleChildScrollView(
        child: Column(
          children: [
            Center(child: _grid()),
            _daySection(wide: false),
          ],
        ),
      );
    },
  );

  Widget _daySection({required bool wide}) {
    return Column(
      mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
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
        if (_known(_date))
          Text(
            _date.weekday > 5
                ? 'Weekend'
                : _sits(_date)
                ? 'Sitting day'
                : 'House not sitting',
            key: const ValueKey('day-status'),
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
        _eventSection(wide),
      ],
    );
  }

  Widget _eventSection(bool wide) {
    final view = LoadView<List<ListingEvent>>(
      key: ValueKey(_date),
      loader: _load,
      builder: (context, events) => ListenableBuilder(
        listenable: widget.library,
        builder: (context, _) {
          final filtered = _applyFilter(events);
          if (filtered.isEmpty) {
            return Center(
              child: Text(
                _date.isAfter(_today)
                    ? 'Nothing scheduled yet.'
                    : 'No proceedings on this day.',
              ),
            );
          }
          final followed = widget.library.follows;
          return ListView(
            shrinkWrap: !wide,
            physics: wide ? null : const NeverScrollableScrollPhysics(),
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
                  onToggleFollow: widget.showFollow
                      ? () => widget.library.setFollowed(
                          followKeyOf(e),
                          !followed.contains(followKeyOf(e)),
                        )
                      : null,
                  progress: widget.library.record(e.id),
                ),
            ],
          );
        },
      ),
    );
    return wide ? Expanded(child: view) : view;
  }
}
