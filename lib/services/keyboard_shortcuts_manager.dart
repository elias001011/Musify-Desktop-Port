/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     Musify is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     Musify is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about Musify, including how to contribute,
 *     please visit: https://github.com/gokadzev/Musify
 */

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/screens/now_playing_page.dart';
import 'package:musify/screens/search_page.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/playlist_download_service.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/flutter_toast.dart';

/// Every action that can be bound to a desktop keyboard shortcut.
enum ShortcutAction {
  playPause,
  nextTrack,
  previousTrack,
  seekForward,
  seekBackward,
  volumeUp,
  volumeDown,
  toggleShuffle,
  cycleRepeat,
  toggleNowPlaying,
  toggleOfflineForCurrentSong,
  focusSearch,
  goBack,
  goHome,
  goSearch,
  goLibrary,
  goSettings,
}

/// Actions that make sense to fire repeatedly while the key is held down.
const Set<ShortcutAction> _repeatableActions = {
  ShortcutAction.seekForward,
  ShortcutAction.seekBackward,
  ShortcutAction.volumeUp,
  ShortcutAction.volumeDown,
};

/// How much a single "volume up/down" shortcut press moves the volume.
const double _volumeStep = 0.05;

/// Stores the desktop shortcut bindings and runs each [ShortcutAction].
class KeyboardShortcutsManager {
  KeyboardShortcutsManager._();

  static const String _storageKey = 'keyboardShortcuts';

  static final ValueNotifier<Map<ShortcutAction, SingleActivator>> bindings =
      ValueNotifier<Map<ShortcutAction, SingleActivator>>(_load());

  /// The out-of-the-box binding for every action.
  static Map<ShortcutAction, SingleActivator> get defaults =>
      <ShortcutAction, SingleActivator>{
        ShortcutAction.playPause: const SingleActivator(
          LogicalKeyboardKey.space,
        ),
        ShortcutAction.nextTrack: const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          control: true,
        ),
        ShortcutAction.previousTrack: const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          control: true,
        ),
        ShortcutAction.seekForward: const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          shift: true,
        ),
        ShortcutAction.seekBackward: const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          shift: true,
        ),
        ShortcutAction.volumeUp: const SingleActivator(
          LogicalKeyboardKey.arrowUp,
          control: true,
        ),
        ShortcutAction.volumeDown: const SingleActivator(
          LogicalKeyboardKey.arrowDown,
          control: true,
        ),
        ShortcutAction.toggleShuffle: const SingleActivator(
          LogicalKeyboardKey.keyS,
          control: true,
        ),
        ShortcutAction.cycleRepeat: const SingleActivator(
          LogicalKeyboardKey.keyR,
          control: true,
        ),
        ShortcutAction.toggleNowPlaying: const SingleActivator(
          LogicalKeyboardKey.keyP,
          control: true,
        ),
        ShortcutAction.toggleOfflineForCurrentSong: const SingleActivator(
          LogicalKeyboardKey.keyD,
          control: true,
        ),
        ShortcutAction.focusSearch: const SingleActivator(
          LogicalKeyboardKey.keyF,
          control: true,
        ),
        ShortcutAction.goBack: const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          alt: true,
        ),
        ShortcutAction.goHome: const SingleActivator(
          LogicalKeyboardKey.digit1,
          control: true,
        ),
        ShortcutAction.goSearch: const SingleActivator(
          LogicalKeyboardKey.digit2,
          control: true,
        ),
        ShortcutAction.goLibrary: const SingleActivator(
          LogicalKeyboardKey.digit3,
          control: true,
        ),
        ShortcutAction.goSettings: const SingleActivator(
          LogicalKeyboardKey.digit4,
          control: true,
        ),
      };

  static Map<ShortcutAction, SingleActivator> _load() {
    final result = Map<ShortcutAction, SingleActivator>.from(defaults);
    final raw = Hive.box('settings').get(_storageKey);
    if (raw is Map) {
      raw.forEach((key, value) {
        final action = _actionFromName(key?.toString());
        final activator = _deserialize(value);
        if (action != null && activator != null) {
          result[action] = activator;
        }
      });
    }
    return result;
  }

  /// After a backup restore rewrites the `settings` box.
  static void reload() {
    bindings.value = _load();
  }

  static Future<void> setBinding(
    ShortcutAction action,
    SingleActivator activator,
  ) async {
    final updated = Map<ShortcutAction, SingleActivator>.from(bindings.value)
      ..[action] = activator;
    bindings.value = updated;
    await _persist();
  }

  static Future<void> resetToDefaults() async {
    bindings.value = Map<ShortcutAction, SingleActivator>.from(defaults);
    await Hive.box('settings').delete(_storageKey);
  }

  /// The action already bound to [activator], if any, ignoring [ignore].
  static ShortcutAction? conflictingAction(
    SingleActivator activator, {
    ShortcutAction? ignore,
  }) {
    for (final entry in bindings.value.entries) {
      if (entry.key == ignore) continue;
      if (_sameActivator(entry.value, activator)) return entry.key;
    }
    return null;
  }

  static Future<void> _persist() async {
    final map = <String, dynamic>{};
    bindings.value.forEach((action, activator) {
      map[action.name] = _serialize(activator);
    });
    await Hive.box('settings').put(_storageKey, map);
  }

  static Map<String, dynamic> _serialize(SingleActivator activator) => {
    'keyId': activator.trigger.keyId,
    'control': activator.control,
    'shift': activator.shift,
    'alt': activator.alt,
    'meta': activator.meta,
  };

  static SingleActivator? _deserialize(dynamic value) {
    if (value is! Map) return null;
    final keyId = value['keyId'];
    if (keyId is! int) return null;
    return SingleActivator(
      LogicalKeyboardKey.findKeyByKeyId(keyId) ?? LogicalKeyboardKey(keyId),
      control: value['control'] == true,
      shift: value['shift'] == true,
      alt: value['alt'] == true,
      meta: value['meta'] == true,
    );
  }

  static ShortcutAction? _actionFromName(String? name) {
    for (final action in ShortcutAction.values) {
      if (action.name == name) return action;
    }
    return null;
  }

  static bool _sameActivator(SingleActivator a, SingleActivator b) =>
      a.trigger == b.trigger &&
      a.control == b.control &&
      a.shift == b.shift &&
      a.alt == b.alt &&
      a.meta == b.meta;

  /// The keys of [activator] in order, e.g. `['Ctrl', '→']`.
  static List<String> keyLabels(SingleActivator activator) => [
    if (activator.control) 'Ctrl',
    if (activator.shift) 'Shift',
    if (activator.alt) 'Alt',
    if (activator.meta) 'Meta',
    _keyLabel(activator.trigger),
  ];

  static String describe(SingleActivator activator) =>
      keyLabels(activator).join(' + ');

  static String _keyLabel(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.space) return 'Space';
    if (key == LogicalKeyboardKey.arrowUp) return '↑';
    if (key == LogicalKeyboardKey.arrowDown) return '↓';
    if (key == LogicalKeyboardKey.arrowLeft) return '←';
    if (key == LogicalKeyboardKey.arrowRight) return '→';
    if (key == LogicalKeyboardKey.enter) return 'Enter';
    if (key == LogicalKeyboardKey.numpadEnter) return 'Numpad Enter';
    if (key == LogicalKeyboardKey.escape) return 'Esc';
    if (key == LogicalKeyboardKey.tab) return 'Tab';
    final label = key.keyLabel;
    if (label.isNotEmpty) {
      return label.length == 1 ? label.toUpperCase() : label;
    }
    return key.debugName ?? 'Key ${key.keyId}';
  }

  static void invoke(ShortcutAction action) {
    switch (action) {
      case ShortcutAction.playPause:
        if (audioHandler.audioPlayer.playing) {
          audioHandler.pause();
        } else {
          audioHandler.play();
        }
      case ShortcutAction.nextTrack:
        audioHandler.skipToNext();
      case ShortcutAction.previousTrack:
        audioHandler.skipToPrevious();
      case ShortcutAction.seekForward:
        audioHandler.fastForward();
      case ShortcutAction.seekBackward:
        audioHandler.rewind();
      case ShortcutAction.volumeUp:
        audioHandler.setVolume(
          (audioHandler.volume + _volumeStep).clamp(0.0, 1.0),
        );
      case ShortcutAction.volumeDown:
        audioHandler.setVolume(
          (audioHandler.volume - _volumeStep).clamp(0.0, 1.0),
        );
      case ShortcutAction.toggleShuffle:
        audioHandler.setShuffleMode(
          shuffleNotifier.value
              ? AudioServiceShuffleMode.none
              : AudioServiceShuffleMode.all,
        );
      case ShortcutAction.cycleRepeat:
        // Same cycle as the repeat button in now_playing_controls.dart.
        final AudioServiceRepeatMode nextRepeat;
        switch (repeatNotifier.value) {
          case AudioServiceRepeatMode.none:
            nextRepeat = (audioHandler.queue.value.length <= 1)
                ? AudioServiceRepeatMode.one
                : AudioServiceRepeatMode.all;
          case AudioServiceRepeatMode.all:
            nextRepeat = AudioServiceRepeatMode.one;
          default:
            nextRepeat = AudioServiceRepeatMode.none;
        }
        repeatNotifier.value = nextRepeat;
        audioHandler.setRepeatMode(nextRepeat);
      case ShortcutAction.toggleNowPlaying:
        final navigator = NavigationManager.parentNavigatorKey.currentState;
        if (navigator == null) break;
        if (_isPlayerOnTop(navigator)) {
          navigator.pop();
        } else if (audioHandler.mediaItem.value != null) {
          navigator.push(buildNowPlayingRoute());
        }
      case ShortcutAction.toggleOfflineForCurrentSong:
        final song = audioHandler.currentSong;
        final ytid = song == null ? null : song['ytid']?.toString();
        if (song == null || ytid == null || ytid.isEmpty) break;
        unawaited(_toggleCurrentSongOffline(song, ytid));
      case ShortcutAction.focusSearch:
        NavigationManager.router.go(NavigationManager.searchPath);
        requestSearchFocus();
      case ShortcutAction.goBack:
        final navigator = NavigationManager.parentNavigatorKey.currentState;
        if (navigator != null) {
          if (_isPlayerOnTop(navigator)) {
            navigator.pop();
            break;
          }
        }
        if (NavigationManager.router.canPop()) {
          NavigationManager.router.pop();
        }
      case ShortcutAction.goHome:
        NavigationManager.router.go(NavigationManager.homePath);
      case ShortcutAction.goSearch:
        NavigationManager.router.go(NavigationManager.searchPath);
      case ShortcutAction.goLibrary:
        NavigationManager.router.go(NavigationManager.libraryPath);
      case ShortcutAction.goSettings:
        NavigationManager.router.go(NavigationManager.settingsPath);
    }
  }

  /// Reads the live stack, so a fast double press never stacks two players.
  static bool _isPlayerOnTop(NavigatorState navigator) {
    var onTop = false;
    navigator.popUntil((route) {
      onTop = route.settings.name == nowPlayingRouteName;
      return true;
    });
    return onTop;
  }

  /// Same as the offline action in the song menu (`song_bar.dart`).
  static Future<void> _toggleCurrentSongOffline(Map song, String ytid) async {
    final alreadyOffline = isSongAlreadyOffline(ytid);
    try {
      final success = alreadyOffline
          ? await OfflinePlaylistService().removeSongFromOfflineAndResync(ytid)
          : await makeSongOffline(song);

      final context = NavigationManager().context;
      if (!success || !context.mounted) return;
      showToast(
        context,
        alreadyOffline
            ? context.l10n!.songRemovedFromOffline
            : context.l10n!.songAddedToOffline,
      );
    } catch (e, stackTrace) {
      logger.log(
        'KeyboardShortcutsManager: error toggling offline status',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}

typedef _ShortcutMatcher = ({ShortcutAction action, SingleActivator activator});

/// Runs the bound actions app-wide, except while a text field has focus.
class GlobalShortcuts extends StatelessWidget {
  const GlobalShortcuts({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<ShortcutAction, SingleActivator>>(
      valueListenable: KeyboardShortcutsManager.bindings,
      builder: (context, bindings, _) {
        final matchers = <_ShortcutMatcher>[
          for (final entry in bindings.entries)
            (
              action: entry.key,
              activator: SingleActivator(
                entry.value.trigger,
                control: entry.value.control,
                shift: entry.value.shift,
                alt: entry.value.alt,
                meta: entry.value.meta,
                includeRepeats: _repeatableActions.contains(entry.key),
              ),
            ),
        ];
        return Focus(
          autofocus: true,
          skipTraversal: true,
          onKeyEvent: (node, event) => _onKeyEvent(matchers, event),
          child: child,
        );
      },
    );
  }

  KeyEventResult _onKeyEvent(List<_ShortcutMatcher> matchers, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (_isEditingText()) return KeyEventResult.ignored;

    final isRepeat = event is KeyRepeatEvent;
    final keyboard = HardwareKeyboard.instance;

    for (final matcher in matchers) {
      if (isRepeat && !_repeatableActions.contains(matcher.action)) continue;
      if (matcher.activator.accepts(event, keyboard)) {
        KeyboardShortcutsManager.invoke(matcher.action);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  bool _isEditingText() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    if (context.widget is EditableText) return true;
    return context.findAncestorWidgetOfExactType<EditableText>() != null;
  }
}
