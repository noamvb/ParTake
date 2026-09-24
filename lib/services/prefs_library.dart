import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:parlvu/parlvu.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/library.dart';

class PrefsLibrary extends ChangeNotifier implements Library {
  PrefsLibrary(this._prefs) {
    _follows = (_prefs.getStringList('follows') ?? []).toSet();
    final code = _prefs.getString('settings.language');
    _settings = AppSettings(
      language: AudioLanguage.fromCode(code ?? '') ?? AudioLanguage.floor,
      captions: _prefs.getBool('settings.captions') ?? true,
    );
    final raw = _prefs.getString('history');
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            try {
              if (item is! Map) {
                throw const FormatException('entry is not a map');
              }
              final record = WatchRecord.fromJson(
                Map<String, Object?>.from(item),
              );
              _records[record.eventId] = record;
            } catch (e) {
              debugPrint('PrefsLibrary: dropped history entry: $e');
            }
          }
        } else {
          debugPrint(
            'PrefsLibrary: dropped history entry: history is not a list',
          );
        }
      } catch (e) {
        debugPrint('PrefsLibrary: dropped history entry: $e');
      }
    }
  }

  final SharedPreferences _prefs;
  late Set<String> _follows;
  final Map<int, WatchRecord> _records = {};
  late AppSettings _settings;

  @override
  Set<String> get follows => Set.unmodifiable(_follows);

  @override
  Future<void> setFollowed(String key, bool followed) async {
    followed ? _follows.add(key) : _follows.remove(key);
    await _prefs.setStringList('follows', _follows.toList());
    notifyListeners();
  }

  @override
  List<WatchRecord> get continueWatching {
    final records = _records.values.where((r) => !r.finished).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(records.take(20));
  }

  @override
  WatchRecord? record(int eventId) => _records[eventId];

  @override
  Future<void> saveProgress(WatchRecord record) async {
    _records[record.eventId] = record;
    if (_records.length > 200) {
      final oldest = _records.values.toList()
        ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      for (final item in oldest.take(_records.length - 200)) {
        _records.remove(item.eventId);
      }
    }
    await _prefs.setString(
      'history',
      jsonEncode(_records.values.map((r) => r.toJson()).toList()),
    );
    notifyListeners();
  }

  @override
  AppSettings get settings => _settings;

  @override
  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
    await _prefs.setString('settings.language', settings.language.code);
    await _prefs.setBool('settings.captions', settings.captions);
    notifyListeners();
  }
}
