import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/ai/ai_tool_input.dart';

/// Every one of these used to throw out of the tool call, get misread as a
/// provider crash, and replay the whole turn on the next API key — with the
/// side effects of the first attempt already applied.
void main() {
  group('normalizeToolInput', () {
    test('accepts a bare string where a song object was expected', () {
      final args = normalizeToolInput('play_song', {'song': 'dQw4w9WgXcQ'});

      expect(args['song'], isA<Map>());
      expect(args['song']['ytid'], 'dQw4w9WgXcQ');
    });

    test('unwraps a single-element list into an object', () {
      final args = normalizeToolInput('play_song', {
        'song': [
          {'ytid': 'abc', 'title': 'Song'},
        ],
      });

      expect(args['song']['ytid'], 'abc');
    });

    test('maps common argument aliases onto the real names', () {
      final args = normalizeToolInput('play_song', {
        'track': {'ytid': 'abc', 'title': 'Song'},
      });

      expect(args.containsKey('song'), isTrue);
      expect(args.containsKey('track'), isFalse);
    });

    test('coerces numbers sent as strings', () {
      final args = normalizeToolInput('queue_action', {
        'action': 'remove',
        'index': '3',
      });

      expect(args['index'], 3);
    });

    test('coerces booleans sent as strings, in either language', () {
      expect(
        normalizeToolInput('create_playlist', {
          'name': 'x',
          'temporary': 'false',
        })['temporary'],
        isFalse,
      );
      expect(
        normalizeToolInput('like_item', {
          'type': 'song',
          'id': 'a',
          'liked': 'sim',
        })['liked'],
        isTrue,
      );
    });

    test('falls back to a valid enum value instead of failing', () {
      final args = normalizeToolInput('queue_action', {'action': 'delete'});

      expect(args['action'], 'view');
    });

    test('clamps limit into the allowed range', () {
      expect(
        normalizeToolInput('search', {'query': 'x', 'limit': 999})['limit'],
        25,
      );
      expect(
        normalizeToolInput('search', {'query': 'x', 'limit': 0})['limit'],
        1,
      );
    });

    test('defaults a playlist to temporary so nothing is silently saved', () {
      final args = normalizeToolInput('create_playlist', {'name': 'Treino'});

      expect(args['temporary'], isTrue);
    });

    test('names an unnamed playlist rather than creating an empty title', () {
      final args = normalizeToolInput('create_playlist', {'name': '   '});

      expect(args['name'], 'Nova playlist');
    });

    test('normalises a song list, dropping entries it cannot read', () {
      final args = normalizeToolInput('create_playlist', {
        'name': 'x',
        'songs': [
          {'ytid': 'a', 'title': 'A'},
          'b',
          null,
          42,
        ],
      });

      final songs = args['songs'] as List;
      expect(songs, hasLength(2));
      expect(songs.first['ytid'], 'a');
      expect(songs.last['ytid'], 'b');
    });

    test('accepts id/videoId as the song identifier', () {
      final args = normalizeToolInput('play_song', {
        'song': {'id': 'xyz', 'title': 'Song'},
      });

      expect(args['song']['ytid'], 'xyz');
    });

    test('drops a key it cannot make sense of instead of throwing', () {
      final args = normalizeToolInput('queue_action', {
        'action': 'remove',
        'index': 'not a number',
      });

      expect(args.containsKey('index'), isFalse);
    });
  });
}
