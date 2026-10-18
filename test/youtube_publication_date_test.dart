import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// Regression coverage for the vendored YouTube parser.
// ignore: implementation_imports
import 'package:youtube_explode_dart/src/extensions/helpers_extension.dart';
// ignore: implementation_imports
import 'package:youtube_explode_dart/src/reverse_engineering/clients/related_videos_client.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

const _channel = 'UC38IQsAvIsxxjztdMZQtwHA';
const _id = 'dQw4w9WgXcQ';

Map<String, dynamic> _compact(String label) => {
  'compactVideoRenderer': {
    'videoId': _id,
    'title': {'simpleText': 'Song'},
    'longBylineText': {
      'runs': [
        {
          'text': 'Artist',
          'navigationEndpoint': {
            'browseEndpoint': {'browseId': _channel},
          },
        },
      ],
    },
    'publishedTimeText': {'simpleText': label},
    'lengthText': {'simpleText': '3:30'},
    'viewCountText': {'simpleText': 'No views'},
  },
};

void main() {
  test('relative dates accept livestream prefixes and flexible whitespace', () {
    final before = DateTime.now().subtract(const Duration(days: 2));
    for (final label in [
      '2 days ago',
      'Streamed 2 days ago',
      'Streamed live 2 days ago',
      'Premiered 2 days ago',
      '  Streamed   2 DAYS ago ',
    ]) {
      expect(
        label.toDateTime()!.difference(before).abs(),
        lessThan(const Duration(seconds: 2)),
      );
    }
  });

  test('unknown dates cannot abort a list of playable videos', () {
    for (final label in <String?>[
      null,
      '',
      'Streamed',
      'Streamed 2 days',
      'Streamed yesterday ago',
      'Premiered on Oct 13, 2026',
      '1 century ago',
      '-2 days ago',
      '999999999999999999999 years ago',
    ]) {
      expect(label.toDateTime(), isNull, reason: label);
    }
  });

  test(
    'a related video with unfamiliar publication text preserves the list',
    () {
      final videos = RelatedVideosClient([
        _compact('Streamed 2 days'),
        _compact('1 day ago'),
      ]).relatedVideos().toList();
      expect(videos, hasLength(2));
      expect(videos.first.uploadDate, isNull);
      expect(videos.last.uploadDate, isNotNull);
      expect(videos.first.engagement.viewCount, 0);
    },
  );

  test('related counts retain comma-separated and abbreviated values', () {
    for (final entry in {'1,234 views': 1234, '1.5K views': 1500}.entries) {
      final fixture = _compact('1 day ago');
      (fixture['compactVideoRenderer'] as Map)['viewCountText'] = {
        'simpleText': entry.key,
      };
      expect(
        RelatedVideosClient([fixture])
            .relatedVideos()
            .single
            .engagement
            .viewCount,
        entry.value,
      );
    }
  });

  test('search retains videos when YouTube returns an unfamiliar date', () async {
    final video = {
      'videoRenderer': {
        'videoId': _id,
        'title': {
          'runs': [
            {'text': 'Song'},
          ],
        },
        'ownerText': {
          'runs': [
            {
              'text': 'Artist',
              'navigationEndpoint': {
                'browseEndpoint': {'browseId': _channel},
              },
            },
          ],
        },
        'lengthText': {'simpleText': '3:30'},
        'publishedTimeText': {'simpleText': 'Streamed 2 days'},
      },
    };
    final data = {
      'contents': {
        'twoColumnSearchResultsRenderer': {
          'primaryContents': {
            'sectionListRenderer': {
              'contents': [
                {
                  'itemSectionRenderer': {
                    'contents': [video],
                  },
                },
              ],
            },
          },
        },
      },
    };
    final client = YoutubeHttpClient(
      MockClient(
        (request) async => http.Response(
          '<html><script>var ytInitialData = ${jsonEncode(data)};</script></html>',
          200,
          request: request,
        ),
      ),
    );
    addTearDown(client.close);
    final results = await SearchClient(client).search('Song');
    expect(results, hasLength(1));
    expect(results.single.title, 'Song');
    expect(results.single.uploadDate, isNull);
  });
}
