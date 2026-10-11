import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/library.dart';
import 'watch_client.dart';
import 'watch_models.dart';

class WatchFollows extends ChangeNotifier {
  WatchFollows({
    required this._prefs,
    required this._library,
    required this._defaultAddress,
    WatchClient Function(Uri address, String token)? clientFactory,
  }) : _clientFactory =
           clientFactory ??
           ((address, token) => WatchClient(address: address, token: token)) {
    final raw = _prefs.getString('watch.cache');
    if (raw != null) {
      try {
        _cache = WatchFollowList.fromJson(jsonDecode(raw));
      } catch (error) {
        debugPrint('WatchFollows: dropped cache: $error');
      }
    }
    _library.addListener(_libraryChanged);
  }

  final SharedPreferences _prefs;
  final Library _library;
  final String _defaultAddress;
  final WatchClient Function(Uri address, String token) _clientFactory;
  WatchClient? _client;
  WatchFollowList? _cache;
  bool _syncing = false;
  bool _rerun = false;
  bool _applying = false;
  bool _disposed = false;
  Future<void>? _running;
  Future<void> _edits = Future<void>.value();
  String? _lastError;
  DateTime? _lastSyncedAt;

  String get address => _prefs.getString('watch.address') ?? _defaultAddress;
  String get token => _prefs.getString('watch.token') ?? '';
  List<WatchFollow> get follows => _cache?.follows ?? const [];
  bool get syncing => _syncing;
  String? get lastError => _lastError;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  Set<String> get _base =>
      (_prefs.getStringList('watch.legacySynced') ?? []).toSet();

  WatchClient get _api {
    final uri = Uri.tryParse(address);
    if (uri == null ||
        !uri.hasAuthority ||
        !['http', 'https'].contains(uri.scheme)) {
      throw const WatchHttpException(0, 'Invalid address');
    }
    return _client ??= _clientFactory(uri, token);
  }

  Future<List<WatchMember>> members(String q) => _api.members(q);
  Future<List<WatchBill>> bills(String q) => _api.bills(q);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _libraryChanged() {
    if (!_applying &&
        address.isNotEmpty &&
        !setEquals(_library.follows, _base)) {
      unawaited(sync());
    }
  }

  Future<void> configure({
    required String address,
    required String token,
  }) async {
    if (_running != null) await _running;
    await _edits;
    await _prefs.setString('watch.address', address.trim());
    await _prefs.setString('watch.token', token);
    _client?.close();
    _client = null;
    _changed();
    await sync();
  }

  Future<void> sync() {
    if (_running != null) {
      _rerun = true;
      return _running!;
    }
    if (address.isEmpty || _disposed) return Future<void>.value();
    final edits = _edits;
    final done = Completer<void>();
    _running = done.future;
    _syncing = true;
    _changed();
    unawaited(_drain(done, edits));
    return done.future;
  }

  Future<void> _drain(Completer<void> done, Future<void> edits) async {
    try {
      await edits;
      await _guard(_syncOnce);
      if (_rerun) {
        _rerun = false;
        await _guard(_syncOnce);
      }
    } finally {
      _rerun = false;
      _running = null;
      _syncing = false;
      _changed();
      done.complete();
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on WatchUnauthorized {
      _lastError = 'Wrong token';
    } on WatchHttpException catch (error) {
      _lastError = error.status == 0
          ? 'Deck unreachable'
          : 'Deck error ${error.status}';
    } on WatchConflict {
      _lastError = 'Deck changed; try again';
    } on FormatException {
      _lastError = 'Deck response invalid';
    }
    _changed();
  }

  Set<String> _legacy(List<WatchFollow> list) =>
      list.map(legacyKeyOf).whereType<String>().toSet();

  Future<void> _syncOnce() async {
    if (_prefs.getBool('watch.imported') != true) {
      final keys = _library.follows.toList()..sort();
      await _api.importKeys(keys);
      await _prefs.setBool('watch.imported', true);
      _changed();
    }
    var server = await _api.getFollows();
    for (var attempt = 0; attempt < 2; attempt++) {
      final base = _base;
      final local = _library.follows;
      final remote = _legacy(server.follows);
      final result =
          {...base, ...local.difference(base), ...remote.difference(base)}
            ..removeAll(base.difference(local))
            ..removeAll(base.difference(remote));
      if (!setEquals(result, remote)) {
        final added = result.difference(remote).toList()..sort();
        final next = [
          for (final follow in server.follows)
            if (legacyKeyOf(follow) == null ||
                result.contains(legacyKeyOf(follow)))
              follow,
          ...added.map(legacyFollow),
        ];
        try {
          server = await _api.putFollows(server.version, next);
        } on WatchConflict catch (conflict) {
          if (attempt == 1) rethrow;
          server = conflict.current;
          continue;
        }
      }
      await _save(server, result);
      return;
    }
  }

  Future<void> _save(
    WatchFollowList list,
    Set<String> legacy, {
    Set<String>? base,
  }) async {
    _applying = true;
    try {
      final local = _library.follows;
      for (final key in local.difference(legacy)) {
        await _library.setFollowed(key, false);
      }
      for (final key in legacy.difference(local)) {
        await _library.setFollowed(key, true);
      }
      await _prefs.setString('watch.cache', jsonEncode(list.toJson()));
      await _prefs.setStringList(
        'watch.legacySynced',
        (base ?? legacy).toList()..sort(),
      );
      _cache = list;
      _lastError = null;
      _lastSyncedAt = DateTime.now();
    } finally {
      _applying = false;
    }
    _changed();
  }

  Future<void> add(WatchFollow follow) =>
      _edit((list) => [...list, follow], legacyKeyOf(follow), true);

  Future<void> remove(String id) {
    String? key;
    for (final follow in follows) {
      if (follow.id == id) key = legacyKeyOf(follow);
    }
    return _edit((list) => list.where((f) => f.id != id).toList(), key, false);
  }

  Future<void> _edit(
    List<WatchFollow> Function(List<WatchFollow>) change,
    String? key,
    bool adding,
  ) {
    // Capture the current sync before enqueuing; a later sync waits for edits.
    final running = _running;
    _edits = _edits.then((_) async {
      if (running != null) await running;
      await _guard(() async {
        var current = _cache ?? WatchFollowList(version: 0, follows: []);
        WatchFollowList result;
        try {
          result = await _api.putFollows(
            current.version,
            change(current.follows),
          );
        } on WatchConflict catch (conflict) {
          current = conflict.current;
          result = await _api.putFollows(
            current.version,
            change(current.follows),
          );
        }
        final legacy = _library.follows.toSet();
        if (key != null) {
          adding ? legacy.add(key) : legacy.remove(key);
        }
        // Nonlegacy edits preserve unsynced local stars and the merge base.
        if (key == null) {
          await _prefs.setString('watch.cache', jsonEncode(result.toJson()));
          _cache = result;
          _lastError = null;
          _lastSyncedAt = DateTime.now();
          _changed();
        } else {
          final base = _base;
          adding ? base.add(key) : base.remove(key);
          await _save(result, legacy, base: base);
        }
      });
    });
    return _edits;
  }

  @override
  void dispose() {
    _disposed = true;
    _library.removeListener(_libraryChanged);
    _client?.close();
    super.dispose();
  }
}
