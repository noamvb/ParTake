import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:partake/watch/watch_follows.dart';
import 'package:partake/watch/watch_models.dart';

import '../fakes.dart';
import 'fake_watch_server.dart';
import 'watch_models_test.dart' show seamList;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late FakeLibrary library;
  late FakeWatchServer server;
  late WatchFollows watch;
  Future<void> setup({
    List<String> base = const [],
    List<String> local = const [],
    List<WatchFollow> remote = const [],
    bool imported = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      'watch.imported': imported,
      'watch.legacySynced': base,
    });
    prefs = await SharedPreferences.getInstance();
    library = FakeLibrary();
    for (final key in local) {
      await library.setFollowed(key, true);
    }
    server = FakeWatchServer(remote);
    watch = WatchFollows(
      prefs: prefs,
      library: library,
      defaultAddress: 'http://deck.test',
      clientFactory: server.client,
    );
    addTearDown(watch.dispose);
  }

  Set<String> keys(List<WatchFollow> follows) =>
      follows.map(legacyKeyOf).whereType<String>().toSet();
  test('8 first sync imports sorted keys only once', () async {
    await setup(local: ['PM-QP', 'ETHI'], imported: false);
    await watch.sync();
    expect(server.imports, [
      ['ETHI', 'PM-QP'],
    ]);
    expect(server.requests.take(2).map((r) => r.method), ['POST', 'GET']);
    expect(prefs.getBool('watch.imported'), isTrue);
    expect(prefs.getStringList('watch.legacySynced')!.toSet(), {
      'ETHI',
      'PM-QP',
    });
    expect(library.follows, {'ETHI', 'PM-QP'});
    await watch.sync();
    expect(server.imports, hasLength(1));
  });
  test('9 server addition updates local without PUT', () async {
    await setup(
      base: ['ETHI'],
      local: ['ETHI'],
      remote: ['ETHI', 'HOC'].map(legacyFollow).toList(),
    );
    await watch.sync();
    expect(library.follows, {'ETHI', 'HOC'});
    expect(server.puts, isEmpty);
  });
  test('10 local removal drops untouched server key', () async {
    await setup(
      base: ['ETHI', 'HOC'],
      local: ['HOC'],
      remote: ['ETHI', 'HOC'].map(legacyFollow).toList(),
    );
    await watch.sync();
    expect(server.puts, hasLength(1));
    expect(keys(server.puts.single), {'HOC'});
    expect(library.follows, {'HOC'});
  });
  test('11 both additions merge and preserve topic', () async {
    final topic = seamList().follows[2];
    await setup(
      base: ['ETHI'],
      local: ['ETHI', 'FEWO'],
      remote: [legacyFollow('ETHI'), legacyFollow('PM-QP'), topic],
    );
    await watch.sync();
    expect(server.puts, hasLength(1));
    expect(keys(server.puts.single), {'ETHI', 'FEWO', 'PM-QP'});
    expect(server.puts.single.any((f) => f.id == topic.id), isTrue);
    expect(library.follows, {'ETHI', 'FEWO', 'PM-QP'});
  });
  test('12 add retries conflict preserving concurrent MP', () async {
    await setup();
    final mp = seamList().follows[4];
    server.conflict = [mp];
    await watch.add(seamList().follows[2]);
    expect(server.puts, hasLength(2));
    expect(watch.follows.map((f) => f.kind), ['mp', 'topic']);
    expect(prefs.getString('watch.cache'), isNotNull);
  });
  test(
    '13 offline preserves local cache and base then recovery writes cache',
    () async {
      await setup(
        base: ['ETHI'],
        local: ['ETHI'],
        remote: [legacyFollow('HOC')],
      );
      final cache = prefs.getString('watch.cache');
      final base = prefs.getStringList('watch.legacySynced');
      server.offline = true;
      await watch.sync();
      expect(watch.lastError, 'Deck unreachable');
      expect(library.follows, {'ETHI'});
      expect(prefs.getString('watch.cache'), cache);
      expect(prefs.getStringList('watch.legacySynced'), base);
      server.offline = false;
      await watch.sync();
      expect(prefs.getString('watch.cache'), isNotNull);
      expect(watch.lastError, isNull);
    },
  );
  test('14 local star triggers sync and committee PUT', () async {
    await setup(
      base: ['ETHI'],
      local: ['ETHI'],
      remote: [legacyFollow('ETHI')],
    );
    await watch.sync();
    await library.setFollowed('FEWO', true);
    await pumpEventQueue();
    expect(server.puts, hasLength(1));
    expect(
      server.puts.single.any(
        (f) => f.kind == 'committee' && f.committeeCode == 'FEWO',
      ),
      isTrue,
    );
    expect(prefs.getStringList('watch.legacySynced')!.toSet(), {
      'ETHI',
      'FEWO',
    });
  });
}
