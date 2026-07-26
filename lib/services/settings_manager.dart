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
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:musify/screens/playlist_page.dart';
import 'package:musify/screens/user_songs_page.dart';
import 'package:musify/utilities/language_utils.dart';

// Preferences

final shouldWeCheckUpdates = ValueNotifier<bool?>(
  Hive.box('settings').get('shouldWeCheckUpdates', defaultValue: null),
);

final playNextSongAutomatically = ValueNotifier<bool>(
  Hive.box('settings').get('playNextSongAutomatically', defaultValue: false),
);

final useSystemColor = ValueNotifier<bool>(
  Hive.box('settings').get('useSystemColor', defaultValue: true),
);

final usePureBlackColor = ValueNotifier<bool>(
  Hive.box('settings').get('usePureBlackColor', defaultValue: false),
);

final offlineMode = ValueNotifier<bool>(
  Hive.box('settings').get('offlineMode', defaultValue: false),
);

final wrappedEnabled = ValueNotifier<bool>(
  Hive.box('settings').get('wrappedEnabled', defaultValue: true),
);

final predictiveBack = ValueNotifier<bool>(
  Hive.box('settings').get('predictiveBack', defaultValue: true),
);

final sponsorBlockSupport = ValueNotifier<bool>(
  Hive.box('settings').get('sponsorBlockSupport', defaultValue: false),
);

final externalRecommendations = ValueNotifier<bool>(
  Hive.box('settings').get('externalRecommendations', defaultValue: false),
);

final useProxy = ValueNotifier<bool>(
  Hive.box('settings').get('useProxy', defaultValue: false),
);

final audioQualitySetting = ValueNotifier<String>(
  Hive.box('settings').get('audioQuality', defaultValue: 'high'),
);

List<double> _readEqualizerGains() {
  final raw = Hive.box(
    'settings',
  ).get('equalizerBandGains', defaultValue: const <dynamic>[]);

  if (raw is List) {
    return raw.map((value) => value is num ? value.toDouble() : 0.0).toList();
  }

  return <double>[];
}

final equalizerEnabled = ValueNotifier<bool>(
  Hive.box('settings').get('equalizerEnabled', defaultValue: false),
);

final equalizerBandGains = ValueNotifier<List<double>>(_readEqualizerGains());

Locale languageSetting = getLocaleFromLanguageCode(
  Hive.box('settings').get('languageCode', defaultValue: 'en') as String,
);

int themeModeSetting =
    Hive.box('settings').get('themeIndex', defaultValue: 0) as int;

String playlistSortSetting = Hive.box(
  'settings',
).get('playlistSortType', defaultValue: PlaylistSortType.default_.name);

String offlineSortSetting = Hive.box(
  'settings',
).get('offlineSortType', defaultValue: OfflineSortType.default_.name);

Color primaryColorSetting = Color(
  Hive.box('settings').get('accentColor', defaultValue: 0xff91cef4),
);

final shuffleNotifier = ValueNotifier<bool>(
  Hive.box('settings').get('shuffleEnabled', defaultValue: false),
);

final repeatNotifier = ValueNotifier<AudioServiceRepeatMode>(
  AudioServiceRepeatMode.values[Hive.box(
    'settings',
  ).get('repeatMode', defaultValue: 0)],
);

final cloudSyncEnabled = ValueNotifier<bool>(
  Hive.box('settings').get('cloudSyncEnabled', defaultValue: false),
);

// Musify AI (experimental AI DJ) settings

const defaultAiProviderOrder = ['groq', 'gemini', 'openrouter'];

const defaultAiProviderConfig = {
  'groq': {'model': 'llama-3.3-70b-versatile'},
  'gemini': {'model': 'gemini-3.1-flash-lite'},
  'openrouter': {'model': 'openrouter/free'},
};

final aiEnabled = ValueNotifier<bool>(
  Hive.box('settings').get('aiEnabled', defaultValue: false),
);

final aiName = ValueNotifier<String>(
  Hive.box('settings').get('aiName', defaultValue: 'Musify AI'),
);

List<String> _readAiProviderOrder() {
  final raw = Hive.box(
    'settings',
  ).get('aiProviderOrder', defaultValue: defaultAiProviderOrder);
  if (raw is List) {
    return raw.map((value) => value.toString()).toList();
  }
  return List<String>.from(defaultAiProviderOrder);
}

Map<String, Map<String, Object>> _readAiProviders() {
  final raw = Hive.box(
    'settings',
  ).get('aiProviders', defaultValue: <dynamic, dynamic>{});
  final result = <String, Map<String, Object>>{};
  for (final providerId in defaultAiProviderOrder) {
    final defaults = defaultAiProviderConfig[providerId]!;
    final stored = (raw is Map ? raw[providerId] : null) as Map?;
    final rawKeys = stored?['apiKeys'];
    result[providerId] = {
      'apiKeys': rawKeys is List
          ? rawKeys.map((k) => k.toString()).where((k) => k.isNotEmpty).toList()
          : <String>[],
      'model': (stored?['model'] ?? defaults['model']).toString(),
    };
  }
  return result;
}

final aiProviderOrder = ValueNotifier<List<String>>(_readAiProviderOrder());

/// Each provider config is `{'apiKeys': List<String>, 'model': String}`.
/// Multiple keys let the same provider rotate to the next key (e.g. on a
/// rate limit) before Musify AI gives up on it and falls back to the next
/// provider in [aiProviderOrder].
final aiProviders = ValueNotifier<Map<String, Map<String, Object>>>(
  _readAiProviders(),
);

Map<String, Map<String, Object>> _cloneAiProviders() {
  return aiProviders.value.map(
    (key, value) => MapEntry(key, {
      'apiKeys': List<String>.from(value['apiKeys']! as List),
      'model': value['model']!,
    }),
  );
}

Future<void> _persistAiProviders() async {
  await Hive.box('settings').put('aiProviders', aiProviders.value);
}

Future<void> setAiProviderModel(String providerId, String model) async {
  final updated = _cloneAiProviders();
  final current = updated[providerId] ?? {'apiKeys': <String>[], 'model': ''};
  updated[providerId] = {...current, 'model': model};
  aiProviders.value = updated;
  await _persistAiProviders();
}

Future<void> setAiProviderKeys(String providerId, List<String> keys) async {
  final updated = _cloneAiProviders();
  final current = updated[providerId] ?? {'apiKeys': <String>[], 'model': ''};
  updated[providerId] = {
    ...current,
    'apiKeys': keys.map((k) => k.trim()).where((k) => k.isNotEmpty).toList(),
  };
  aiProviders.value = updated;
  await _persistAiProviders();
}

Future<void> updateAiProviderOrder(List<String> order) async {
  aiProviderOrder.value = order;
  await Hive.box('settings').put('aiProviderOrder', order);
}

Map<String, bool> _readAiToolsEnabled() {
  final raw = Hive.box(
    'settings',
  ).get('aiToolsEnabled', defaultValue: <dynamic, dynamic>{});
  if (raw is Map) {
    return raw.map((k, v) => MapEntry(k.toString(), v != false));
  }
  return {};
}

/// Per-tool on/off switches for Musify AI. A tool absent from this map is
/// treated as enabled - it only needs an entry once the user turns it off.
final aiToolsEnabled = ValueNotifier<Map<String, bool>>(_readAiToolsEnabled());

Future<void> setAiToolEnabled(String toolName, bool enabled) async {
  final updated = Map<String, bool>.from(aiToolsEnabled.value);
  updated[toolName] = enabled;
  aiToolsEnabled.value = updated;
  await Hive.box('settings').put('aiToolsEnabled', updated);
}

/// When on, the user's recently played songs are folded straight into the
/// system prompt every turn instead of behind a tool call - cheaper and
/// faster than making the model ask for them explicitly.
final aiIncludeRecentlyPlayed = ValueNotifier<bool>(
  Hive.box('settings').get('aiIncludeRecentlyPlayed', defaultValue: true),
);

Future<void> setAiIncludeRecentlyPlayed(bool value) async {
  aiIncludeRecentlyPlayed.value = value;
  await Hive.box('settings').put('aiIncludeRecentlyPlayed', value);
}

final cloudSyncAutomatic = ValueNotifier<bool>(
  Hive.box('settings').get('cloudSyncAutomatic', defaultValue: true),
);

final cloudSyncConfigured = ValueNotifier<bool>(
  Hive.box(
    'settings',
  ).get('cloudSyncAccountId', defaultValue: '').toString().isNotEmpty,
);

final cloudSyncLastSyncedAt = ValueNotifier<DateTime?>(
  _readDateTimeSetting('cloudSyncLastSyncedAt'),
);

final cloudSyncStatus = ValueNotifier<String>('Cloud sync is idle');

final appStateReloadSignal = ValueNotifier<int>(0);

// Non-storage notifiers

var sleepTimerNotifier = ValueNotifier<Duration?>(null);

// Server-Notifiers

final announcementURL = ValueNotifier<String?>(null);

DateTime? _readDateTimeSetting(String key) {
  final value = Hive.box('settings').get(key);
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

void refreshSettingsFromStorage() {
  final settingsBox = Hive.box('settings');

  shouldWeCheckUpdates.value = settingsBox.get(
    'shouldWeCheckUpdates',
    defaultValue: null,
  );
  playNextSongAutomatically.value = settingsBox.get(
    'playNextSongAutomatically',
    defaultValue: false,
  );
  useSystemColor.value = settingsBox.get('useSystemColor', defaultValue: true);
  usePureBlackColor.value = settingsBox.get(
    'usePureBlackColor',
    defaultValue: false,
  );
  offlineMode.value = settingsBox.get('offlineMode', defaultValue: false);
  predictiveBack.value = settingsBox.get('predictiveBack', defaultValue: true);
  sponsorBlockSupport.value = settingsBox.get(
    'sponsorBlockSupport',
    defaultValue: false,
  );
  externalRecommendations.value = settingsBox.get(
    'externalRecommendations',
    defaultValue: false,
  );
  useProxy.value = settingsBox.get('useProxy', defaultValue: false);
  audioQualitySetting.value = settingsBox.get(
    'audioQuality',
    defaultValue: 'high',
  );
  equalizerEnabled.value = settingsBox.get(
    'equalizerEnabled',
    defaultValue: false,
  );
  equalizerBandGains.value = _readEqualizerGains();
  languageSetting = getLocaleFromLanguageCode(
    settingsBox.get('languageCode', defaultValue: 'en') as String,
  );
  themeModeSetting = settingsBox.get('themeIndex', defaultValue: 0) as int;
  playlistSortSetting = settingsBox.get(
    'playlistSortType',
    defaultValue: PlaylistSortType.default_.name,
  );
  offlineSortSetting = settingsBox.get(
    'offlineSortType',
    defaultValue: OfflineSortType.default_.name,
  );
  primaryColorSetting = Color(
    settingsBox.get('accentColor', defaultValue: 0xff91cef4),
  );
  shuffleNotifier.value = settingsBox.get(
    'shuffleEnabled',
    defaultValue: false,
  );
  repeatNotifier.value = AudioServiceRepeatMode
      .values[settingsBox.get('repeatMode', defaultValue: 0)];
  cloudSyncEnabled.value = settingsBox.get(
    'cloudSyncEnabled',
    defaultValue: false,
  );
  cloudSyncAutomatic.value = settingsBox.get(
    'cloudSyncAutomatic',
    defaultValue: true,
  );
  cloudSyncConfigured.value = settingsBox
      .get('cloudSyncAccountId', defaultValue: '')
      .toString()
      .isNotEmpty;
  cloudSyncLastSyncedAt.value = _readDateTimeSetting('cloudSyncLastSyncedAt');
  aiEnabled.value = settingsBox.get('aiEnabled', defaultValue: false);
  aiName.value = settingsBox.get('aiName', defaultValue: 'Musify AI');
  // The assistant used to be called "Musify IA". Users who never renamed it
  // have that literal persisted, so the default alone would never reach them.
  if (aiName.value == 'Musify IA') {
    aiName.value = 'Musify AI';
    unawaited(settingsBox.put('aiName', aiName.value));
  }
  aiProviderOrder.value = _readAiProviderOrder();
  aiProviders.value = _readAiProviders();
  aiToolsEnabled.value = _readAiToolsEnabled();
  aiIncludeRecentlyPlayed.value = settingsBox.get(
    'aiIncludeRecentlyPlayed',
    defaultValue: true,
  );
}

Future<void> setAiEnabled(bool value) async {
  aiEnabled.value = value;
  await Hive.box('settings').put('aiEnabled', value);
}

Future<void> setAiName(String value) async {
  final trimmed = value.trim();
  aiName.value = trimmed.isEmpty ? 'Musify AI' : trimmed;
  await Hive.box('settings').put('aiName', aiName.value);
}
