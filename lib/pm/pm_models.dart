import 'package:flutter/foundation.dart';

@immutable
class Place {
  Place.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      country = j['country'] as String,
      lat = (j['lat'] as num?)?.toDouble(),
      lon = (j['lon'] as num?)?.toDouble(),
      zone = j['zone'] as String?;
  final String id, name, country;
  final double? lat, lon;
  final String? zone;
}

@immutable
class PmEvent {
  PmEvent.fromJson(Map<String, dynamic> j)
    : date = j['date'] as String,
      localTime = j['local_time'] as String,
      startsAt = j['starts_at'] == null ? null : DateTime.parse(j['starts_at']),
      place = Place.fromJson(j['place']),
      text = j['text'] as String,
      venue = j['venue'] as String?,
      media = j['media'] as String?,
      itemId = j['item_id'] as String;
  final String date, localTime, text, itemId;
  final DateTime? startsAt;
  final Place place;
  final String? venue, media;
}

@immutable
class PmDay {
  PmDay.fromJson(Map<String, dynamic> j)
    : date = j['date'] as String,
      itemId = j['item_id'] as String,
      url = j['url'] as String,
      notes = List.unmodifiable((j['notes'] as List).cast<String>()),
      events = List.unmodifiable(
        (j['events'] as List).map((e) => PmEvent.fromJson(e)),
      );
  final String date, itemId, url;
  final List<String> notes;
  final List<PmEvent> events;
}

@immutable
class PmNow {
  const PmNow({this.place, this.event});
  PmNow.fromJson(Map<String, dynamic> j)
    : place = j['place'] == null ? null : Place.fromJson(j['place']),
      event = j['event'] == null ? null : PmEvent.fromJson(j['event']);
  final Place? place;
  final PmEvent? event;
}

@immutable
class PmToday {
  PmToday.fromJson(Map<String, dynamic> j)
    : days = List.unmodifiable(
        (j['days'] as List).map((d) => PmDay.fromJson(d)),
      ),
      now = PmNow.fromJson(j['now']),
      next = j['next'] == null ? null : PmEvent.fromJson(j['next']),
      fetchedAt = DateTime.parse(j['fetched_at']);
  final List<PmDay> days;
  final PmNow now;
  final PmEvent? next;
  final DateTime fetchedAt;
}

@immutable
class FeedItem {
  FeedItem.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      type = j['type'] as String,
      title = j['title'] as String,
      publishedAt = DateTime.parse(j['published_at']),
      url = j['url'] as String,
      summary = j['summary'] as String;
  final String id, type, title, url, summary;
  final DateTime publishedAt;
}

@immutable
class PmSource {
  PmSource.fromJson(Map<String, dynamic> j)
    : name = j['name'] as String,
      url = j['url'] as String;
  final String name, url;
}

@immutable
class FeedPage {
  FeedPage.fromJson(Map<String, dynamic> j)
    : items = List.unmodifiable(
        (j['items'] as List).map((i) => FeedItem.fromJson(i)),
      ),
      next = j['next'] as String?,
      source = PmSource.fromJson(j['source']);
  final List<FeedItem> items;
  final String? next;
  final PmSource source;
}

@immutable
class PmItem {
  PmItem.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      type = j['type'] as String,
      title = j['title'] as String,
      publishedAt = DateTime.parse(j['published_at']),
      url = j['url'] as String,
      body = j['body'] as String,
      text = j['text'] as String,
      events = List.unmodifiable(
        (j['events'] as List).map((e) => PmEvent.fromJson(e)),
      );
  final String id, type, title, url, body, text;
  final DateTime publishedAt;
  final List<PmEvent> events;
}

@immutable
class MapPlace extends Place {
  MapPlace.fromJson(super.j)
    : visits = (j['visits'] as num).toInt(),
      days = (j['days'] as num).toInt(),
      first = j['first'] as String,
      last = j['last'] as String,
      super.fromJson();
  final int visits, days;
  final String first, last;
}

@immutable
class PathStop {
  PathStop.fromJson(Map<String, dynamic> j)
    : date = j['date'] as String,
      place = Place.fromJson(j['place']),
      firstTime = j['first_time'] as String,
      events = (j['events'] as num).toInt();
  final String date, firstTime;
  final Place place;
  final int events;
}
