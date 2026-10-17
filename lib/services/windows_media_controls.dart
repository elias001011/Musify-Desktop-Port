import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Mirrors the existing audio handler into the Windows runner's SMTC session.
/// The player remains the source of truth, including for commands from Windows.
class WindowsMediaControls {
  WindowsMediaControls({
    required this.onError,
    this.channel = const MethodChannel('musify/media_controls'),
  });

  final void Function(Object error, StackTrace stackTrace) onError;
  final MethodChannel channel;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  AudioHandler? _handler;
  MediaItem? _item;
  PlaybackState _state = PlaybackState();
  Map<String, Object?>? _lastUpdate;
  Future<void> _pending = Future.value();
  bool _disposed = false;

  Future<void> start(AudioHandler handler) async {
    _handler = handler;
    channel.setMethodCallHandler(_onMethodCall);
    try {
      await channel.invokeMethod<void>('initialize');
    } catch (_) {
      channel.setMethodCallHandler(null);
      rethrow;
    }
    _subscriptions.addAll([
      handler.mediaItem.listen((item) {
        _item = item;
        _scheduleUpdate();
      }),
      handler.playbackState.listen((state) {
        _state = state;
        _scheduleUpdate();
      }),
    ]);
  }

  bool get _active =>
      _item != null &&
      _state.processingState != AudioProcessingState.idle &&
      _state.processingState != AudioProcessingState.completed &&
      _state.processingState != AudioProcessingState.error;

  void _scheduleUpdate() {
    // Serialize native calls and read the latest values when they run, so a
    // rapid track change cannot leave an older title/cover in the media card.
    _pending = _pending
        .then((_) async {
          if (_disposed) return;
          final artUri = _item?.artUri;
          final update = <String, Object?>{
            'enabled': _active,
            'status': !_active
                ? 'stopped'
                : _state.playing
                ? 'playing'
                : 'paused',
            'title': _item?.title ?? '',
            'artist': _item?.artist ?? '',
            'album': _item?.album ?? '',
            'artUri': artUri?.scheme == 'http' || artUri?.scheme == 'https'
                ? artUri.toString()
                : '',
            'artPath': artUri?.scheme == 'file'
                ? artUri!.toFilePath(windows: true)
                : '',
          };
          // Playback progress ticks do not need to refresh the Windows media card.
          if (mapEquals(update, _lastUpdate)) return;
          await channel.invokeMethod<void>('update', update);
          _lastUpdate = update;
        })
        .catchError((Object error, StackTrace stackTrace) {
          onError(error, stackTrace);
        });
  }

  Future<void> _onMethodCall(MethodCall call) async {
    if (_disposed || !_active || call.method != 'button') return;
    try {
      switch (call.arguments) {
        case 'play':
          await _handler!.play();
        case 'pause':
          await _handler!.pause();
        case 'next':
          await _handler!.skipToNext();
        case 'previous':
          await _handler!.skipToPrevious();
        case 'stop':
          await _handler!.stop();
      }
    } catch (error, stackTrace) {
      onError(error, stackTrace);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    channel.setMethodCallHandler(null);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _pending;
    try {
      await channel.invokeMethod<void>('dispose');
    } catch (error, stackTrace) {
      onError(error, stackTrace);
    }
  }
}
