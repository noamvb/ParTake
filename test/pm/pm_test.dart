import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:partake/pm/pm_client.dart';
import 'package:partake/pm/pm_models.dart';
import 'package:partake/pm/pm_logic.dart';
import 'package:partake/watch/watch_client.dart';

Map<String, dynamic> seam(String name) =>
    jsonDecode(File('test/pm/${name}_seam.json').readAsStringSync());

void main() {
  test('1 models decode all five seam responses', () {
    final today = PmToday.fromJson(seam('today'));
    expect(today.days, hasLength(2));
    expect(today.days.first.events.first.place.zone, 'Europe/Paris');
    expect(today.fetchedAt, DateTime.utc(2026, 7, 15, 8));
    expect(
      FeedPage.fromJson(seam('feed')).source.name,
      'Prime Minister’s Office',
    );
    expect(PmItem.fromJson(seam('item')).text, contains('Second paragraph.'));
    final place = MapPlace.fromJson(seam('places')['places'][0]);
    expect(
      [place.visits, place.days, place.first, place.last],
      [14, 9, '2025-03-21', '2026-07-15'],
    );
    expect(PathStop.fromJson(seam('path')['stops'][0]).events, 3);
    expect(() => today.days.clear(), throwsUnsupportedError);
  });
  test('2 nullable venue and media decode', () {
    final event = PmEvent.fromJson({
      ...seam('today')['days'][0]['events'][0],
      'venue': null,
      'media': null,
      'extra': true,
    });
    expect(event.venue, isNull);
    expect(event.media, isNull);
  });
  test('3 before first event retains previous itinerary place', () {
    final data = PmToday.fromJson(seam('today'));
    final state = nowAndNext(data, DateTime.utc(2026, 7, 15, 11));
    expect(state.now.event, isNull);
    expect(state.now.place?.id, 'ottawa-ontario');
    expect(state.next?.text, 'Community meeting');
  });
  test('4 between and after events recomputes state', () {
    final data = PmToday.fromJson(seam('today'));
    final between = nowAndNext(data, DateTime.utc(2026, 7, 15, 13));
    expect(between.now.event?.text, 'Community meeting');
    expect(between.next?.text, 'Bilateral meeting');
    final after = nowAndNext(
      PmToday.fromJson({
        ...seam('today'),
        'days': [seam('today')['days'][0]],
      }),
      DateTime.utc(2026, 7, 15, 20),
    );
    expect(after.now.event?.text, 'Bilateral meeting');
    expect(after.next, isNull);
    final tomorrow = nowAndNext(data, DateTime.utc(2026, 7, 16, 5));
    expect(tomorrow.now.event, isNull);
    expect(tomorrow.now.place?.id, 'unknown');
  });
  test('5 Ottawa label converts summer Paris time', () {
    final days = PmToday.fromJson(seam('today')).days;
    expect(ottawaLabel(days.first.events.first), '08:00 Ottawa');
    expect(ottawaLabel(days.last.events.first), isNull);
    expect(ottawaLabel(days.first.events.last), isNull);
  });
  test('6 Deck client paths preserve item slashes', () async {
    final urls = <String>[];
    final client = PmClient(
      address: Uri.parse('http://deck.test'),
      client: MockClient((r) async {
        urls.add(r.url.toString());
        final name = r.url.path.contains('/items/')
            ? 'item'
            : r.url.path.split('/').last;
        return http.Response.bytes(utf8.encode(jsonEncode(seam(name))), 200);
      }),
    );
    addTearDown(client.close);
    await client.today();
    await client.feed(type: 'readout', before: 'c1');
    await client.item('readouts/2026/10/14/x');
    expect(urls, [
      'http://deck.test/watch/api/pm/today',
      'http://deck.test/watch/api/pm/feed?type=readout&limit=50&before=c1',
      'http://deck.test/watch/api/pm/items/readouts/2026/10/14/x',
    ]);
  });
  test('7 snapshot filters feed places and path locally', () async {
    final urls = <Uri>[];
    final client = PmClient.snapshot(
      base: Uri.parse('https://test/snap/'),
      client: MockClient((r) async {
        urls.add(r.url);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode(seam(r.url.path.split('/').last.split('.').first)),
          ),
          200,
        );
      }),
    );
    addTearDown(client.close);
    final page = await client.feed(type: 'readout', before: 'ignored');
    expect(urls.single.toString(), 'https://test/snap/pm/feed.json');
    expect(page.items.single.type, 'readout');
    expect(page.next, isNull);
    await expectLater(client.item('x'), throwsUnsupportedError);
    final stops = await client.path(
      since: DateTime.utc(2026, 7, 15),
      until: DateTime.utc(2026, 7, 15),
    );
    expect(stops.single.place.id, 'paris-france');
    final places = await client.places(since: DateTime.utc(2026, 7, 1));
    expect(places.single.visits, 14);
  });
  test('8 HTTP errors retain status and message', () async {
    final client = PmClient(
      address: Uri.parse('http://deck.test'),
      client: MockClient((_) async => http.Response('{"error":"boom"}', 500)),
    );
    addTearDown(client.close);
    await expectLater(
      client.today(),
      throwsA(
        isA<WatchHttpException>()
            .having((e) => e.status, 'status', 500)
            .having((e) => e.message, 'message', 'boom'),
      ),
    );
  });
}
