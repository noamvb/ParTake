import 'dart:convert';

import 'package:http/http.dart' as http;

/// The release version this build was made from, set by CI with
/// `--dart-define=PARTAKE_VERSION=0.7.0`. Empty in local builds, which then
/// never check for updates.
const partakeVersion = String.fromEnvironment('PARTAKE_VERSION');

class UpdateInfo {
  const UpdateInfo({required this.version, required this.url});
  final String version; // e.g. '0.8.0', no leading v
  final Uri url; // the release's html_url
}

List<BigInt>? _versionParts(String version) {
  final match = RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$').firstMatch(version);
  if (match == null || match.end != version.length) return null;
  return version.split('.').map(BigInt.parse).toList();
}

/// True when [tag] is a strictly newer numeric MAJOR.MINOR.PATCH version.
/// Removes one leading 'v' from the tag; malformed versions return false.
bool isNewerVersion(String current, String tag) {
  final before = _versionParts(current);
  final after = _versionParts(tag.startsWith('v') ? tag.substring(1) : tag);
  if (before == null || after == null) return false;
  for (var i = 0; i < 3; i++) {
    if (after[i] != before[i]) return after[i] > before[i];
  }
  return false;
}

class UpdateChecker {
  UpdateChecker({required this.currentVersion, this.client});

  final String currentVersion;
  final http.Client? client;

  /// Checks GitHub's latest release. Local builds make no request; malformed
  /// responses, older releases and network failures return null.
  Future<UpdateInfo?> check() async {
    if (currentVersion.isEmpty) return null;
    http.Client? requestClient;
    try {
      requestClient = client ?? http.Client();
      final response = await requestClient.get(
        Uri.parse(
          'https://api.github.com/repos/noamvb/ParTake/releases/latest',
        ),
        headers: {'Accept': 'application/vnd.github+json'},
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;
      final tag = body['tag_name'];
      final urlText = body['html_url'];
      if (tag is! String || urlText is! String) return null;
      if (!isNewerVersion(currentVersion, tag)) return null;
      final url = Uri.tryParse(urlText);
      if (url == null ||
          (url.scheme != 'https' && url.scheme != 'http') ||
          url.host.isEmpty) {
        return null;
      }
      return UpdateInfo(
        version: tag.startsWith('v') ? tag.substring(1) : tag,
        url: url,
      );
    } catch (_) {
      return null;
    } finally {
      if (client == null) requestClient?.close();
    }
  }
}
