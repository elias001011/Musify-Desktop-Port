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
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:musify/services/backed_up_state_manager.dart';
import 'package:musify/services/settings_manager.dart';

class CloudSyncManager {
  CloudSyncManager._();

  static final CloudSyncManager instance = CloudSyncManager._();

  static const String endpoint = String.fromEnvironment(
    'MUSIFY_CLOUD_SYNC_URL',
  );

  static const Duration _uploadDebounce = Duration(seconds: 20);
  static const String _accountIdKey = 'cloudSyncAccountId';
  static const String _automaticKey = 'cloudSyncAutomatic';
  static const String _deviceIdKey = 'cloudSyncDeviceId';
  static const String _enabledKey = 'cloudSyncEnabled';
  static const String _lastLocalChangeAtKey = 'cloudSyncLastLocalChangeAt';
  static const String _lastSyncedAtKey = 'cloudSyncLastSyncedAt';
  static const String _dateTimeMarker = '__musifyType';
  static const String _transportEncoding = 'gzip+base64-json';

  final http.Client _client = http.Client();

  StreamSubscription<BoxEvent>? _settingsSubscription;
  StreamSubscription<BoxEvent>? _userSubscription;
  Timer? _uploadTimer;
  bool _applyingRemoteSnapshot = false;
  bool _initialised = false;

  bool get isSupportedPlatform =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isLinux ||
          Platform.isWindows);

  bool get isAvailable => isSupportedPlatform && endpoint.trim().isNotEmpty;

  Future<void> initialise() async {
    if (_initialised) return;
    _initialised = true;

    if (!isSupportedPlatform) {
      return;
    }

    await _ensureDeviceId();
    await rebindStorageListeners();

    if (!isAvailable) {
      cloudSyncStatus.value =
          'Cloud sync backend is not configured for this build';
      return;
    }

    if (cloudSyncEnabled.value && _accountId.isNotEmpty && !offlineMode.value) {
      unawaited(
        synchronize(allowUpload: cloudSyncAutomatic.value, reason: 'startup'),
      );
    }
  }

  Future<void> rebindStorageListeners() async {
    if (!isSupportedPlatform) {
      return;
    }

    await _settingsSubscription?.cancel();
    await _userSubscription?.cancel();

    _settingsSubscription = Hive.box(
      'settings',
    ).watch().listen((event) => _handleLocalChange('settings', event.key));
    _userSubscription = Hive.box(
      'user',
    ).watch().listen((event) => _handleLocalChange('user', event.key));
  }

  void markBackedUpStateChanged() {
    _handleLocalChange('user', 'manualRestore');
  }

  Future<({String message, bool success})> connect(String passphrase) async {
    final trimmedPassphrase = passphrase.trim();
    if (!isAvailable) {
      return (
        message: 'Cloud sync backend is not configured for this build',
        success: false,
      );
    }
    if (trimmedPassphrase.length < 8) {
      return (
        message: 'Use a passphrase with at least 8 characters',
        success: false,
      );
    }

    cloudSyncStatus.value = 'Connecting to cloud sync...';

    try {
      final accountId = _accountIdForPassphrase(trimmedPassphrase);
      await _putInternalSetting(_accountIdKey, accountId);
      await _putInternalSetting(_enabledKey, true);
      await _putInternalSetting(_automaticKey, true);
      refreshSettingsFromStorage();

      final remoteSnapshot = await _downloadSnapshot(accountId);
      if (remoteSnapshot == null) {
        return uploadNow(messagePrefix: 'Created cloud backup');
      }

      await _applySnapshot(remoteSnapshot);
      cloudSyncStatus.value = 'Loaded backup from cloud';
      return (message: 'Loaded backup from cloud', success: true);
    } catch (e) {
      cloudSyncStatus.value = 'Cloud sync setup failed';
      return (message: 'Cloud sync setup failed: $e', success: false);
    }
  }

  Future<({String message, bool success})> setEnabled(bool enabled) async {
    if (enabled && _accountId.isEmpty) {
      return (
        message: 'Enter your cloud sync passphrase first',
        success: false,
      );
    }
    if (enabled && !isAvailable) {
      return (
        message: 'Cloud sync backend is not configured for this build',
        success: false,
      );
    }

    await _putInternalSetting(_enabledKey, enabled);
    refreshSettingsFromStorage();
    cloudSyncStatus.value = enabled ? 'Cloud sync enabled' : 'Cloud sync off';

    if (enabled) {
      unawaited(
        synchronize(allowUpload: cloudSyncAutomatic.value, reason: 'enabled'),
      );
    } else {
      _uploadTimer?.cancel();
    }

    return (
      message: enabled ? 'Cloud sync enabled' : 'Cloud sync disabled',
      success: true,
    );
  }

  Future<({String message, bool success})> setAutomaticUploads(
    bool enabled,
  ) async {
    await _putInternalSetting(_automaticKey, enabled);
    refreshSettingsFromStorage();
    cloudSyncStatus.value = enabled
        ? 'Automatic cloud uploads enabled'
        : 'Automatic cloud uploads disabled';

    if (enabled && cloudSyncEnabled.value) {
      unawaited(synchronize(reason: 'automatic uploads enabled'));
    } else {
      _uploadTimer?.cancel();
    }

    return (
      message: enabled
          ? 'Automatic cloud uploads enabled'
          : 'Automatic cloud uploads disabled',
      success: true,
    );
  }

  Future<({String message, bool success})> synchronize({
    bool allowUpload = true,
    String reason = 'manual',
  }) async {
    if (!_canSync) {
      return (message: _unavailableMessage, success: false);
    }

    cloudSyncStatus.value = 'Checking cloud backup...';

    try {
      final remoteSnapshot = await _downloadSnapshot(_accountId);
      if (remoteSnapshot == null) {
        if (!allowUpload) {
          cloudSyncStatus.value = 'No cloud backup found';
          return (
            message:
                'No cloud backup found. Use Upload local backup to create one.',
            success: false,
          );
        }
        return uploadNow(messagePrefix: 'Uploaded first cloud backup');
      }

      final remoteUpdatedAt = _snapshotUpdatedAt(remoteSnapshot);
      final localChangedAt = _readDateTimeSetting(_lastLocalChangeAtKey);

      if (localChangedAt == null ||
          (remoteUpdatedAt != null &&
              remoteUpdatedAt.isAfter(localChangedAt))) {
        await _applySnapshot(remoteSnapshot);
        cloudSyncStatus.value = 'Loaded newer backup from cloud';
        return (message: 'Loaded newer backup from cloud', success: true);
      }

      if (!allowUpload) {
        cloudSyncStatus.value = 'Local backup is newer';
        return (
          message: 'Local backup is newer. Use Upload local backup to send it.',
          success: true,
        );
      }

      return uploadNow(messagePrefix: 'Uploaded latest local backup');
    } catch (e) {
      cloudSyncStatus.value = 'Cloud sync failed';
      return (message: 'Cloud sync failed: $e', success: false);
    }
  }

  Future<({String message, bool success})> uploadNow({
    String messagePrefix = 'Uploaded cloud backup',
  }) async {
    if (!_canSync) {
      return (message: _unavailableMessage, success: false);
    }

    _uploadTimer?.cancel();
    cloudSyncStatus.value = 'Uploading cloud backup...';

    try {
      final snapshot = await _createSnapshot();
      final updatedAt = DateTime.parse(snapshot['updatedAt'].toString());
      final uri = _recordUri(_accountId);
      final body = _encodeSnapshotForTransport(snapshot);
      final response = await _client.put(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == HttpStatus.requestEntityTooLarge) {
          throw HttpException(
            'PUT ${uri.path} returned 413. Cloud backup is too large for the current backend limit.',
          );
        }
        throw HttpException('PUT ${uri.path} returned ${response.statusCode}');
      }

      await _putInternalSetting(_lastSyncedAtKey, updatedAt.toIso8601String());
      await _putInternalSetting(
        _lastLocalChangeAtKey,
        updatedAt.toIso8601String(),
      );
      refreshSettingsFromStorage();
      cloudSyncStatus.value = messagePrefix;
      return (message: messagePrefix, success: true);
    } catch (e) {
      cloudSyncStatus.value = 'Cloud upload failed';
      return (message: 'Cloud upload failed: $e', success: false);
    }
  }

  Future<({String message, bool success})> downloadNow() async {
    if (!_canSync) {
      return (message: _unavailableMessage, success: false);
    }

    cloudSyncStatus.value = 'Downloading cloud backup...';

    try {
      final remoteSnapshot = await _downloadSnapshot(_accountId);
      if (remoteSnapshot == null) {
        cloudSyncStatus.value = 'No cloud backup found';
        return (message: 'No cloud backup found', success: false);
      }

      await _applySnapshot(remoteSnapshot);
      cloudSyncStatus.value = 'Loaded backup from cloud';
      return (message: 'Loaded backup from cloud', success: true);
    } catch (e) {
      cloudSyncStatus.value = 'Cloud download failed';
      return (message: 'Cloud download failed: $e', success: false);
    }
  }

  Future<void> dispose() async {
    _uploadTimer?.cancel();
    await _settingsSubscription?.cancel();
    await _userSubscription?.cancel();
    _client.close();
  }

  bool get _canSync =>
      isAvailable &&
      !offlineMode.value &&
      cloudSyncEnabled.value &&
      _accountId.isNotEmpty;

  String get _accountId =>
      Hive.box('settings').get(_accountIdKey, defaultValue: '').toString();

  String get _unavailableMessage {
    if (!isAvailable) {
      return 'Cloud sync backend is not configured for this build';
    }
    if (!cloudSyncEnabled.value) {
      return 'Cloud sync is disabled';
    }
    if (offlineMode.value) {
      return 'Cloud sync is paused while offline mode is enabled';
    }
    return 'Enter your cloud sync passphrase first';
  }

  void _handleLocalChange(String boxName, dynamic key) {
    if (_applyingRemoteSnapshot) {
      return;
    }
    if (boxName == 'settings' && key.toString() == 'offlineMode') {
      _handleOfflineModeChange();
      return;
    }
    if (boxName == 'settings' && _isInternalSettingKey(key)) {
      return;
    }
    if (boxName != 'settings' && boxName != 'user') {
      return;
    }

    final now = DateTime.now().toUtc();
    unawaited(
      _putInternalSetting(_lastLocalChangeAtKey, now.toIso8601String()),
    );

    if (!offlineMode.value &&
        cloudSyncEnabled.value &&
        cloudSyncAutomatic.value &&
        _accountId.isNotEmpty) {
      _scheduleUpload();
    }
  }

  void _handleOfflineModeChange() {
    if (offlineMode.value) {
      _uploadTimer?.cancel();
      cloudSyncStatus.value =
          'Cloud sync is paused while offline mode is enabled';
      return;
    }

    if (cloudSyncEnabled.value && _accountId.isNotEmpty) {
      unawaited(
        synchronize(
          allowUpload: cloudSyncAutomatic.value,
          reason: 'offline mode disabled',
        ),
      );
    }
  }

  void _scheduleUpload() {
    if (!isAvailable) {
      return;
    }

    cloudSyncStatus.value = 'Cloud upload scheduled';
    _uploadTimer?.cancel();
    _uploadTimer = Timer(
      _uploadDebounce,
      () => unawaited(uploadNow(messagePrefix: 'Auto-uploaded cloud backup')),
    );
  }

  Future<Map<String, dynamic>> _createSnapshot() async {
    final now = DateTime.now().toUtc();
    final deviceId = await _ensureDeviceId();

    return {
      'schemaVersion': 1,
      'updatedAt': now.toIso8601String(),
      'deviceId': deviceId,
      'boxes': {'settings': _exportBox('settings'), 'user': _exportBox('user')},
    };
  }

  Map<String, dynamic> _exportBox(String boxName) {
    final box = Hive.box(boxName);
    final result = <String, dynamic>{};

    for (final key in box.keys) {
      if (boxName == 'settings' && _isLocalOnlySettingKey(key)) {
        continue;
      }

      result[key.toString()] = _encodeValue(box.get(key));
    }

    return result;
  }

  Future<Map<String, dynamic>?> _downloadSnapshot(String accountId) async {
    final uri = _recordUri(accountId);
    final response = await _client.get(
      uri,
      headers: const {'Accept': 'application/json'},
    );

    if (response.statusCode == HttpStatus.notFound) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('GET ${uri.path} returned ${response.statusCode}');
    }

    return _decodeSnapshotFromTransport(response.body);
  }

  Future<void> _applySnapshot(Map<String, dynamic> snapshot) async {
    final boxes = snapshot['boxes'];
    if (boxes is! Map) {
      throw const FormatException('Cloud backup does not contain boxes');
    }

    final remoteUpdatedAt =
        _snapshotUpdatedAt(snapshot) ?? DateTime.now().toUtc();

    _applyingRemoteSnapshot = true;
    try {
      await _replaceBoxData('settings', boxes['settings']);
      await _replaceBoxData('user', boxes['user']);
      await _putInternalSetting(
        _lastSyncedAtKey,
        remoteUpdatedAt.toIso8601String(),
      );
      await _putInternalSetting(
        _lastLocalChangeAtKey,
        remoteUpdatedAt.toIso8601String(),
      );
    } finally {
      _applyingRemoteSnapshot = false;
    }

    refreshBackedUpStateFromStorage();
  }

  Future<void> _replaceBoxData(String boxName, dynamic rawData) async {
    if (rawData is! Map) {
      return;
    }

    final box = Hive.box(boxName);
    final existingKeys = box.keys
        .where((key) => boxName != 'settings' || !_isLocalOnlySettingKey(key))
        .toList();

    for (final key in existingKeys) {
      await box.delete(key);
    }

    for (final entry in rawData.entries) {
      final key = entry.key.toString();
      if (boxName == 'settings' && _isLocalOnlySettingKey(key)) {
        continue;
      }
      await box.put(key, _decodeValue(entry.value));
    }
  }

  dynamic _encodeValue(dynamic value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is DateTime) {
      return {
        _dateTimeMarker: 'DateTime',
        'value': value.toUtc().toIso8601String(),
      };
    }
    if (value is List) {
      return value.map(_encodeValue).toList();
    }
    if (value is Map) {
      return value.map(
        (key, value) => MapEntry(key.toString(), _encodeValue(value)),
      );
    }

    return value.toString();
  }

  dynamic _decodeValue(dynamic value) {
    if (value is List) {
      return value.map(_decodeValue).toList();
    }
    if (value is Map) {
      if (value[_dateTimeMarker] == 'DateTime') {
        return DateTime.tryParse(value['value']?.toString() ?? '') ?? value;
      }

      return value.map(
        (key, value) => MapEntry(key.toString(), _decodeValue(value)),
      );
    }

    return value;
  }

  String _encodeSnapshotForTransport(Map<String, dynamic> snapshot) {
    final snapshotJson = json.encode(snapshot);
    final compressedPayload = base64.encode(
      gzip.encode(utf8.encode(snapshotJson)),
    );
    final compressedJson = json.encode({
      'schemaVersion': 1,
      'encoding': _transportEncoding,
      'payload': compressedPayload,
    });

    return compressedJson.length < snapshotJson.length
        ? compressedJson
        : snapshotJson;
  }

  Map<String, dynamic> _decodeSnapshotFromTransport(String body) {
    final decoded = json.decode(body);
    if (decoded is! Map) {
      throw const FormatException('Cloud backup response is not an object');
    }

    if (decoded['encoding'] == _transportEncoding) {
      final payload = decoded['payload'];
      if (payload is! String || payload.isEmpty) {
        throw const FormatException(
          'Compressed cloud backup is missing payload',
        );
      }

      final decompressedJson = utf8.decode(gzip.decode(base64.decode(payload)));
      final decompressed = json.decode(decompressedJson);
      if (decompressed is! Map) {
        throw const FormatException(
          'Compressed cloud backup payload is not an object',
        );
      }

      return Map<String, dynamic>.from(decompressed);
    }

    return Map<String, dynamic>.from(decoded);
  }

  Uri _recordUri(String accountId) {
    final base = Uri.parse(endpoint);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;

    return base.replace(path: '$basePath/sync/$accountId');
  }

  String _accountIdForPassphrase(String passphrase) {
    final bytes = utf8.encode('musify-cloud-sync-v1:$passphrase');
    return sha256.convert(bytes).toString();
  }

  DateTime? _snapshotUpdatedAt(Map<String, dynamic> snapshot) =>
      DateTime.tryParse(snapshot['updatedAt']?.toString() ?? '');

  Future<String> _ensureDeviceId() async {
    final settingsBox = Hive.box('settings');
    final existing = settingsBox.get(_deviceIdKey, defaultValue: '').toString();
    if (existing.isNotEmpty) {
      return existing;
    }

    final random = Random.secure();
    final randomPart = List<int>.generate(
      8,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    final deviceId =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-$randomPart';
    await _putInternalSetting(_deviceIdKey, deviceId);
    return deviceId;
  }

  Future<void> _putInternalSetting(String key, Object? value) async {
    await Hive.box('settings').put(key, value);
  }

  bool _isInternalSettingKey(dynamic key) =>
      key.toString().startsWith('cloudSync');

  bool _isLocalOnlySettingKey(dynamic key) =>
      _isInternalSettingKey(key) || key.toString() == 'offlineMode';

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
}
