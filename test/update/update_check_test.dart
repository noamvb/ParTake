import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:partake/update/update_check.dart';

void main() {
  test('update 1: newer minor and patch versions', () {
    expect(isNewerVersion('0.7.0', 'v0.8.0'), isTrue);
    expect(isNewerVersion('0.7.0', '0.7.1'), isTrue);
  });
  test('update 2: equal and older versions', () {
    expect(isNewerVersion('0.7.0', 'v0.7.0'), isFalse);
    expect(isNewerVersion('0.8.0', 'v0.7.9'), isFalse);
  });
  test('update 3: compares numerically', () {
    expect(isNewerVersion('0.9.0', 'v0.10.0'), isTrue);
  });
  test('update 4: rejects malformed versions', () {
    for (final tag in ['nightly', 'v1.2', 'v1.2.3-beta']) {
      expect(isNewerVersion('0.7.0', tag), isFalse);
    }
    expect(isNewerVersion('', 'v0.8.0'), isFalse);
  });
  test('update 5: requests latest release and returns info', () async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.github.com/repos/noamvb/ParTake/releases/latest',
      );
      expect(request.headers['Accept'], 'application/vnd.github+json');
      return http.Response(
        '{"tag_name":"v0.8.0","html_url":"https://github.com/noamvb/ParTake/releases/tag/v0.8.0"}',
        200,
      );
    });
    addTearDown(client.close);
    final info = await UpdateChecker(
      currentVersion: '0.7.0',
      client: client,
    ).check();
    expect(info, isNotNull);
    expect(info!.version, '0.8.0');
    expect(
      info.url,
      Uri.parse('https://github.com/noamvb/ParTake/releases/tag/v0.8.0'),
    );
  });
  test('update 6: current release returns null', () async {
    final client = MockClient(
      (_) async => http.Response(
        '{"tag_name":"v0.7.0","html_url":"https://example.com/r"}',
        200,
      ),
    );
    addTearDown(client.close);
    expect(
      await UpdateChecker(currentVersion: '0.7.0', client: client).check(),
      isNull,
    );
  });
  test('update 7: server and network failures return null', () async {
    final server = MockClient((_) async => http.Response('', 500));
    final network = MockClient(
      (_) async => throw http.ClientException('offline'),
    );
    addTearDown(server.close);
    addTearDown(network.close);
    expect(
      await UpdateChecker(currentVersion: '0.7.0', client: server).check(),
      isNull,
    );
    expect(
      await UpdateChecker(currentVersion: '0.7.0', client: network).check(),
      isNull,
    );
  });
  test('update 8: local build makes no request', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response(
        '{"tag_name":"v0.8.0","html_url":"https://example.com/r"}',
        200,
      );
    });
    addTearDown(client.close);
    expect(
      await UpdateChecker(currentVersion: '0.7.0', client: client).check(),
      isNotNull,
    );
    expect(calls, 1);
    calls = 0;
    expect(
      await UpdateChecker(currentVersion: '', client: client).check(),
      isNull,
    );
    expect(calls, 0);
  });
}
