import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../pm/pm_client.dart';
import '../pm/pm_logic.dart';
import '../pm/pm_models.dart';
import 'pm_screen.dart' show pmFailure;

class PmMap extends StatefulWidget {
  const PmMap({
    super.key,
    required this.pm,
    required this.now,
    required this.showTiles,
  });
  final PmClient pm;
  final DateTime Function() now;
  final bool showTiles;
  @override
  State<PmMap> createState() => _PmMapState();
}

class _PmMapState extends State<PmMap> {
  bool _weekMode = false;
  String _range = 'Month';
  late final DateTime _currentWeek;
  late DateTime _week;
  late Future<List<MapPlace>> _places;
  Future<List<PathStop>>? _path;
  int _mapRevision = 0;
  @override
  void initState() {
    super.initState();
    final today = ottawaDate(widget.now());
    _currentWeek = today.subtract(Duration(days: today.weekday - 1));
    _week = _currentWeek;
    _places = widget.pm.places(since: _since());
  }

  DateTime _since() => switch (_range) {
    'Month' => ottawaDate(widget.now()).subtract(const Duration(days: 30)),
    'Year' => ottawaDate(widget.now()).subtract(const Duration(days: 365)),
    _ => DateTime.utc(2025, 3, 14),
  };
  Future<void> _reload() async {
    setState(() {
      _mapRevision++;
      if (_weekMode) {
        _path = widget.pm.path(
          since: _week,
          until: _week.add(const Duration(days: 6)),
        );
      } else {
        _places = widget.pm.places(since: _since());
      }
    });
    try {
      if (_weekMode) {
        await _path;
      } else {
        await _places;
      }
    } catch (_) {
      /* Shown by FutureBuilder. */
    }
  }

  String _date(DateTime date) => date.toIso8601String().substring(0, 10);
  bool _located(Place place) => place.lat != null && place.lon != null;
  LatLng _point(Place place) => LatLng(place.lat!, place.lon!);
  void _showPlace(MapPlace place) => showModalBottomSheet<void>(
    context: context,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(place.name, style: Theme.of(context).textTheme.titleLarge),
            Text('${place.visits} visits · ${place.days} days'),
            Text('First: ${place.first} · Last: ${place.last}'),
          ],
        ),
      ),
    ),
  );
  Widget _map(List<LatLng> points, List<Marker> markers, {bool path = false}) =>
      SizedBox(
        height: 360,
        child: Stack(
          children: [
            FlutterMap(
              key: ValueKey('pm-map-$_mapRevision-$_weekMode'),
              options: MapOptions(
                initialCenter: points.isEmpty
                    ? const LatLng(56, -96)
                    : points.first,
                initialZoom: points.length == 1 ? 5 : 3,
                initialCameraFit: points.length > 1
                    ? CameraFit.coordinates(
                        coordinates: points,
                        padding: const EdgeInsets.all(32),
                        maxZoom: 9,
                      )
                    : null,
              ),
              children: [
                if (widget.showTiles)
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'io.github.noamvb.partake',
                  ),
                if (path && points.length > 1)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: points,
                        color: Theme.of(context).colorScheme.primary,
                        strokeWidth: 3,
                      ),
                    ],
                  ),
                MarkerLayer(markers: markers),
              ],
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Text('© OpenStreetMap contributors'),
                ),
              ),
            ),
          ],
        ),
      );
  Widget _visits(List<MapPlace> places) {
    final located = places.where(_located).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _map(located.map(_point).toList(), [
          for (final place in located)
            Marker(
              point: _point(place),
              width: 2 * math.min(30.0, 6 + 4 * math.sqrt(place.visits)),
              height: 2 * math.min(30.0, 6 + 4 * math.sqrt(place.visits)),
              child: Semantics(
                label: '${place.name}, ${place.visits} visits',
                button: true,
                child: InkWell(
                  key: ValueKey('pm-place-${place.id}'),
                  customBorder: const CircleBorder(),
                  onTap: () => _showPlace(place),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.7),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
        if (places.isEmpty) const Text('No visits in this range.'),
        for (final place in places.where((p) => !_located(p)))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Not on map: ${place.name}'),
            onTap: () => _showPlace(place),
          ),
      ],
    );
  }

  Widget _stops(List<PathStop> stops) {
    final points = stops
        .where((s) => _located(s.place))
        .map((s) => _point(s.place))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _map(points, [
          for (var i = 0; i < stops.length; i++)
            if (_located(stops[i].place))
              Marker(
                point: _point(stops[i].place),
                width: 32,
                height: 32,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
        ], path: true),
        if (stops.isEmpty) const Text('No travel stops this week.'),
        for (var i = 0; i < stops.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Text('${i + 1}'),
            title: Text(
              '${_located(stops[i].place) ? '' : 'Not on map: '}${stops[i].place.name}',
            ),
            subtitle: Text(
              '${stops[i].date} · ${stops[i].firstTime} · ${stops[i].events} events',
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _reload,
    child: ListView(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Visits')),
              ButtonSegment(value: true, label: Text('Week')),
            ],
            selected: {_weekMode},
            onSelectionChanged: (s) {
              setState(() => _weekMode = s.single);
              _reload();
            },
          ),
        ),
        const SizedBox(height: 12),
        if (!_weekMode) ...[
          Wrap(
            spacing: 6,
            children: [
              for (final range in ['Month', 'Year', 'Term'])
                ChoiceChip(
                  label: Text(range),
                  selected: _range == range,
                  onSelected: (_) {
                    _range = range;
                    _reload();
                  },
                ),
            ],
          ),
          FutureBuilder<List<MapPlace>>(
            future: _places,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) return pmFailure(snapshot.error!, _reload);
              return _visits(snapshot.data ?? []);
            },
          ),
        ] else ...[
          Row(
            children: [
              IconButton(
                tooltip: 'Previous week',
                icon: const Icon(Icons.chevron_left),
                onPressed:
                    widget.pm.isSnapshot &&
                        !_week.isAfter(
                          _currentWeek.subtract(const Duration(days: 28)),
                        )
                    ? null
                    : () {
                        _week = _week.subtract(const Duration(days: 7));
                        _reload();
                      },
              ),
              Expanded(
                child: Text(
                  '${_date(_week)} – ${_date(_week.add(const Duration(days: 6)))}',
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: 'Next week',
                icon: const Icon(Icons.chevron_right),
                onPressed: !_week.isBefore(_currentWeek)
                    ? null
                    : () {
                        _week = _week.add(const Duration(days: 7));
                        _reload();
                      },
              ),
            ],
          ),
          FutureBuilder<List<PathStop>>(
            future: _path,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) return pmFailure(snapshot.error!, _reload);
              return _stops(snapshot.data ?? []);
            },
          ),
        ],
      ],
    ),
  );
}
