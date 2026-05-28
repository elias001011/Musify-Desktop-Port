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

final automaticOfflineMode = ValueNotifier<bool>(
  Hive.box('settings').get('automaticOfflineMode', defaultValue: true),
);

final automaticOfflineModeApplied = ValueNotifier<bool>(
  Hive.box('settings').get('automaticOfflineModeApplied', defaultValue: false),
);

final automaticOfflineModeStatus = ValueNotifier<String>(
  'Automatic offline checks are idle',
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
  automaticOfflineMode.value = settingsBox.get(
    'automaticOfflineMode',
    defaultValue: true,
  );
  automaticOfflineModeApplied.value = settingsBox.get(
    'automaticOfflineModeApplied',
    defaultValue: false,
  );
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
}
