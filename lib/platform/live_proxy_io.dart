import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../player/live_playlist.dart';
import 'live_proxy.dart';

LiveProxy? createLiveProxy(Map<String, String> headers) =>
    _IoLiveProxy(headers);

class _IoLiveProxy implements LiveProxy {
  _IoLiveProxy(this.headers);

  final Map<String, String> headers;
  final http.Client _client = http.Client();
  final StreamController<Duration> _edges = StreamController.broadcast();
  HttpServer? _server;
  Uri? _media;
  LivePlaylist _playlist = LivePlaylist();
  DateTime _fetchedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _refreshing;

  @override
  Duration get edge => _playlist.edge;
  @override
  DateTime? get windowStart => _media == null ? null : _playlist.windowStart;
  @override
  Stream<Duration> get edgeStream => _edges.stream;

  Future<String> _get(Uri url) async {
    final response = await _client.get(url, headers: headers);
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    return response.body;
  }

  @override
  Future<Uri?> start(Uri url) async {
    var media = url;
    var text = await _get(url);
    final variant = LivePlaylist.firstVariant(text, url);
    if (variant != null) {
      media = variant;
      text = await _get(variant);
    }
    if (!LivePlaylist.isLiveMedia(text)) return null;
    _media = media;
    _playlist = LivePlaylist()..merge(text, media);
    _fetchedAt = DateTime.now();
    _edges.add(_playlist.edge);
    final server = _server ??= await _serve();
    return Uri.parse(
      'http://${server.address.address}:${server.port}/live.m3u8'
      '?v=${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  Future<HttpServer> _serve() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response;
      try {
        if (request.uri.path != '/live.m3u8' || _media == null) {
          response.statusCode = HttpStatus.notFound;
        } else {
          await _refresh();
          response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
          );
          response.write(_playlist.render());
        }
      } catch (_) {
        response.statusCode = HttpStatus.badGateway;
      }
      await response.close();
    });
    return server;
  }

  Future<void> _refresh() {
    if (DateTime.now().difference(_fetchedAt) < const Duration(seconds: 4)) {
      return Future.value();
    }
    return _refreshing ??= () async {
      try {
        final media = _media!;
        final text = await _get(media);
        if (media != _media) return;
        _playlist.merge(text, media);
        _fetchedAt = DateTime.now();
        _edges.add(_playlist.edge);
      } finally {
        _refreshing = null;
      }
    }();
  }

  @override
  Future<void> close() async {
    _media = null;
    await _server?.close(force: true);
    _server = null;
    _client.close();
    await _edges.close();
  }
}
