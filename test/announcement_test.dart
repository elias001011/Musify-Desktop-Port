import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/services/update_manager.dart';

void main() {
  tearDown(() => announcementURL.value = null);

  test('port announcement is loaded from its own configuration', () async {
    final file =
        jsonDecode(await File('announcement.json').readAsString()) as Map;
    final client = MockClient((request) async {
      expect(request.url.toString(), checkUrl);
      return http.Response(jsonEncode(file), 200);
    });
    await fetchAnnouncementOnly(client: client);
    expect(
      announcementURL.value,
      'https://github.com/elias001011/Musify-Desktop-Port/discussions/17',
    );
    client.close();
  });

  test('a cleared announcement hides the notice', () async {
    announcementURL.value = 'https://example.com/old';
    final client = MockClient(
      (_) async => http.Response('{"announcementurl":null}', 200),
    );
    await fetchAnnouncementOnly(client: client);
    expect(announcementURL.value, isNull);
    client.close();
  });
}
