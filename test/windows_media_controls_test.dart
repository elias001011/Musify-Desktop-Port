import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/windows_media_controls.dart';

const _channel = MethodChannel('musify/media_controls');

class _Handler extends BaseAudioHandler {
  final commands = <String>[];

  @override
  Future<void> play() async => commands.add('play');
  @override
  Future<void> pause() async => commands.add('pause');
  @override
  Future<void> skipToNext() async => commands.add('next');
  @override
  Future<void> skipToPrevious() async => commands.add('previous');
  @override
  Future<void> stop() async => commands.add('stop');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _Handler handler;
  late WindowsMediaControls controls;
  late List<MethodCall> calls;
  late List<Object> errors;
  bool failNextUpdate = false;

  Future<void> flush() => Future<void>.delayed(Duration.zero);
  Map<dynamic, dynamic> getUpdate() =>
      calls.lastWhere((call) => call.method == 'update').arguments as Map;
  Future<void> press(String button) async {
    final reply = Completer<void>();
    await messenger.handlePlatformMessage(
      _channel.name,
      _channel.codec.encodeMethodCall(MethodCall('button', button)),
      (_) => reply.complete(),
    );
    await reply.future;
  }

  setUp(() async {
    handler = _Handler();
    calls = [];
    errors = [];
    failNextUpdate = false;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'update' && failNextUpdate) {
        failNextUpdate = false;
        throw PlatformException(code: 'smtc_error', message: 'Test failure');
      }
      return null;
    });
    controls = WindowsMediaControls(onError: (error, _) => errors.add(error));
    await controls.start(handler);
    await flush();
  });

  tearDown(() async {
    await controls.dispose();
    messenger.setMockMethodCallHandler(_channel, null);
  });

  void play({Uri? artwork}) {
    handler.mediaItem.add(
      MediaItem(
        id: 'track-1',
        title: 'Song',
        artist: 'Artist',
        artUri: artwork,
      ),
    );
    handler.playbackState.add(
      PlaybackState(processingState: AudioProcessingState.ready, playing: true),
    );
  }

  test('does not claim a system media session before playback', () {
    expect(calls.first.method, 'initialize');
    expect(getUpdate()['enabled'], false);
    expect(getUpdate()['status'], 'stopped');
  });

  test('publishes track info and artwork, including nullable album', () async {
    play(artwork: Uri.parse('https://example.com/cover.jpg'));
    await flush();
    expect(getUpdate(), {
      'enabled': true,
      'status': 'playing',
      'title': 'Song',
      'artist': 'Artist',
      'album': '',
      'artUri': 'https://example.com/cover.jpg',
      'artPath': '',
    });
    expect(errors, isEmpty);
  });

  test('passes a decoded Windows path for offline artwork', () async {
    play(artwork: Uri.parse('file:///C:/Music/Caf%C3%A9%20%2B/cover.jpg'));
    await flush();
    expect(getUpdate()['artPath'], r'C:\Music\Café +\cover.jpg');
    expect(getUpdate()['artUri'], '');
  });

  test(
    'routes every system transport button through the audio handler',
    () async {
      play();
      await flush();
      for (final button in ['play', 'pause', 'next', 'previous', 'stop']) {
        await press(button);
      }
      await press('unknown');
      expect(handler.commands, ['play', 'pause', 'next', 'previous', 'stop']);
    },
  );

  test(
    'keeps paused sessions available and ignores progress-only ticks',
    () async {
      play();
      await flush();
      final count = calls.length;
      handler.playbackState.add(
        handler.playbackState.value.copyWith(
          updatePosition: const Duration(seconds: 10),
        ),
      );
      await flush();
      expect(calls, hasLength(count));
      handler.playbackState.add(
        handler.playbackState.value.copyWith(playing: false),
      );
      await flush();
      expect(getUpdate()['enabled'], true);
      expect(getUpdate()['status'], 'paused');
      await press('play');
      expect(handler.commands, ['play']);
    },
  );

  for (final state in [
    AudioProcessingState.idle,
    AudioProcessingState.completed,
    AudioProcessingState.error,
  ]) {
    test(
      '$state releases the session even if the player reports playing',
      () async {
        play();
        await flush();
        handler.playbackState.add(
          PlaybackState(processingState: state, playing: true),
        );
        await flush();
        expect(getUpdate()['enabled'], false);
        expect(getUpdate()['status'], 'stopped');
        await press('next');
        expect(handler.commands, isEmpty);
      },
    );
  }

  test(
    'rapid track changes publish the latest metadata without stale artwork',
    () async {
      play(artwork: Uri.parse('https://example.com/old.jpg'));
      handler.mediaItem.add(const MediaItem(id: 'track-2', title: 'New song'));
      await flush();
      expect(getUpdate()['title'], 'New song');
      expect(getUpdate()['artUri'], '');
      handler.mediaItem.add(null);
      await flush();
      expect(getUpdate()['enabled'], false);
    },
  );

  test(
    'a native update failure is logged and later updates still work',
    () async {
      failNextUpdate = true;
      play();
      await flush();
      expect(errors, hasLength(1));
      handler.mediaItem.add(const MediaItem(id: 'track-2', title: 'Recovered'));
      await flush();
      expect(getUpdate()['title'], 'Recovered');
      expect(getUpdate()['enabled'], true);
    },
  );

  test(
    'disposal stops subscriptions and removes native button handling',
    () async {
      play();
      await flush();
      await controls.dispose();
      final count = calls.length;
      handler.mediaItem.add(
        const MediaItem(id: 'track-2', title: 'After dispose'),
      );
      await flush();
      expect(calls, hasLength(count));
      expect(calls.last.method, 'dispose');
      await press('play');
      expect(handler.commands, isEmpty);
    },
  );
}
