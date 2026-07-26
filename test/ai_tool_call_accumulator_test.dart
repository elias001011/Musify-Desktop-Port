import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/ai/openai_compatible_provider.dart';

/// The streamed tool-call format is the easiest thing in the AI layer to get
/// subtly wrong: arguments arrive as string fragments that are only valid JSON
/// once concatenated, and the fragments for two parallel calls are interleaved
/// and told apart only by `index`.
void main() {
  group('ToolCallAccumulator', () {
    test('joins argument fragments streamed across chunks', () {
      final accumulator = ToolCallAccumulator()
        ..addDelta([
          {
            'index': 0,
            'id': 'call_abc',
            'function': {'name': 'search', 'arguments': ''},
          },
        ])
        ..addDelta([
          {
            'index': 0,
            'function': {'arguments': '{"que'},
          },
        ])
        ..addDelta([
          {
            'index': 0,
            'function': {'arguments': 'ry":"tame imp'},
          },
        ])
        ..addDelta([
          {
            'index': 0,
            'function': {'arguments': 'ala"}'},
          },
        ]);

      final calls = accumulator.build();

      expect(calls, hasLength(1));
      expect(calls.single.id, 'call_abc');
      expect(calls.single.name, 'search');
      expect(calls.single.arguments, {'query': 'tame impala'});
      expect(calls.single.argumentsMalformed, isFalse);
    });

    test('keeps parallel calls apart by index and orders them by it', () {
      final accumulator = ToolCallAccumulator()
        ..addDelta([
          {
            'index': 1,
            'id': 'second',
            'function': {'name': 'get_lyrics', 'arguments': '{"title":'},
          },
          {
            'index': 0,
            'id': 'first',
            'function': {'name': 'search', 'arguments': '{"query":'},
          },
        ])
        ..addDelta([
          {
            'index': 0,
            'function': {'arguments': '"a"}'},
          },
          {
            'index': 1,
            'function': {'arguments': '"b"}'},
          },
        ]);

      final calls = accumulator.build();

      expect(calls.map((c) => c.id), ['first', 'second']);
      expect(calls.first.arguments, {'query': 'a'});
      expect(calls.last.arguments, {'title': 'b'});
    });

    test('flags unparseable arguments instead of silently using {}', () {
      final accumulator = ToolCallAccumulator()
        ..addDelta([
          {
            'index': 0,
            'id': 'call_bad',
            'function': {'name': 'play_song', 'arguments': '{"song": '},
          },
        ]);

      final call = accumulator.build().single;

      expect(call.argumentsMalformed, isTrue);
      expect(call.arguments, isEmpty);
    });

    test('accepts a call with no arguments at all', () {
      final accumulator = ToolCallAccumulator()
        ..addDelta([
          {
            'index': 0,
            'id': 'call_index',
            'function': {'name': 'get_library_index'},
          },
        ]);

      final call = accumulator.build().single;

      expect(call.name, 'get_library_index');
      expect(call.arguments, isEmpty);
      expect(call.argumentsMalformed, isFalse);
    });

    test('falls back to slot 0 when the provider omits index', () {
      final accumulator = ToolCallAccumulator()
        ..addDelta([
          {
            'id': 'call_noindex',
            'function': {'name': 'search', 'arguments': '{"query":"x"}'},
          },
        ]);

      expect(accumulator.build().single.arguments, {'query': 'x'});
    });

    test('synthesises an id when the provider never sends one', () {
      final accumulator = ToolCallAccumulator()
        ..addDelta([
          {
            'index': 0,
            'function': {'name': 'search', 'arguments': '{"query":"x"}'},
          },
        ]);

      expect(accumulator.build().single.id, isNotEmpty);
    });

    test('drops a fragment that never named a tool', () {
      final accumulator = ToolCallAccumulator()
        ..addDelta([
          {
            'index': 0,
            'function': {'arguments': '{"query":"x"}'},
          },
        ]);

      expect(accumulator.build(), isEmpty);
    });
  });
}
