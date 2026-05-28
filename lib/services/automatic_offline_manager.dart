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

import 'package:http/http.dart' as http;
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';

class AutomaticOfflineManager {
  AutomaticOfflineManager._();

  static final AutomaticOfflineManager instance = AutomaticOfflineManager._();

  static const String _autoAppliedKey = 'automaticOfflineModeApplied';
  static const Duration _probeInterval = Duration(seconds: 30);
  static const Duration _probeTimeout = Duration(seconds: 4);
  static const int _failuresBeforeOffline = 3;
  static const int _successesBeforeOnline = 2;

  static final List<Uri> _probeUris = [
    Uri.parse('https://www.gstatic.com/generate_204'),
    Uri.parse('https://cloudflare.com/cdn-cgi/trace'),
    Uri.parse('https://api.github.com/rate_limit'),
  ];

  final http.Client _client = http.Client();

  Timer? _timer;
  bool _checking = false;
  bool _initialised = false;
  int _consecutiveFailures = 0;
  int _consecutiveSuccesses = 0;

  Future<void> initialise() async {
    if (_initialised) return;
    _initialised = true;

    automaticOfflineMode.addListener(_handlePreferenceChanged);

    if (automaticOfflineMode.value) {
      _start();
    } else {
      automaticOfflineModeStatus.value = 'Automatic offline mode is disabled';
    }
  }

  Future<void> dispose() async {
    automaticOfflineMode.removeListener(_handlePreferenceChanged);
    _timer?.cancel();
    _client.close();
  }

  Future<void> setEnabled(bool enabled) async {
    await addOrUpdateData('settings', 'automaticOfflineMode', enabled);
    automaticOfflineMode.value = enabled;

    if (!enabled && _autoApplied) {
      await _setOfflineMode(false, autoApplied: false);
    }
  }

  void markManualOfflineChange() {
    automaticOfflineModeApplied.value = false;
    unawaited(addOrUpdateData('settings', _autoAppliedKey, false));
  }

  void _handlePreferenceChanged() {
    if (automaticOfflineMode.value) {
      _consecutiveFailures = 0;
      _consecutiveSuccesses = 0;
      _start();
    } else {
      _timer?.cancel();
      automaticOfflineModeStatus.value = 'Automatic offline mode is disabled';
      if (_autoApplied) {
        unawaited(_setOfflineMode(false, autoApplied: false));
      }
    }
  }

  void _start() {
    _timer?.cancel();
    automaticOfflineModeStatus.value = 'Checking connection...';
    unawaited(_checkNow());
    _timer = Timer.periodic(_probeInterval, (_) => unawaited(_checkNow()));
  }

  Future<void> _checkNow() async {
    if (_checking || !automaticOfflineMode.value) {
      return;
    }

    _checking = true;
    try {
      final online = await _hasWorkingConnection();
      await _applyConnectivityState(online);
    } finally {
      _checking = false;
    }
  }

  Future<bool> _hasWorkingConnection() async {
    final results = await Future.wait(_probeUris.map(_probeEndpoint));

    return results.any((result) => result);
  }

  Future<bool> _probeEndpoint(Uri uri) async {
    try {
      final response = await _client
          .get(
            uri,
            headers: const {'Accept': '*/*', 'Cache-Control': 'no-cache'},
          )
          .timeout(_probeTimeout);

      if (uri.host == 'www.gstatic.com') {
        return response.statusCode == 204;
      }

      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  Future<void> _applyConnectivityState(bool online) async {
    if (online) {
      _consecutiveFailures = 0;
      _consecutiveSuccesses++;

      if (offlineMode.value && _autoApplied) {
        automaticOfflineModeStatus.value =
            'Connection restored. Waiting for confirmation...';

        if (_consecutiveSuccesses >= _successesBeforeOnline) {
          await _setOfflineMode(false, autoApplied: false);
          automaticOfflineModeStatus.value = 'Connection restored';
        }
        return;
      }

      automaticOfflineModeStatus.value = offlineMode.value
          ? 'Manual offline mode is enabled'
          : 'Connection looks online';
      return;
    }

    _consecutiveSuccesses = 0;
    _consecutiveFailures++;

    if (!offlineMode.value && _consecutiveFailures >= _failuresBeforeOffline) {
      await _setOfflineMode(true, autoApplied: true);
      automaticOfflineModeStatus.value =
          'Connection unavailable. Offline mode enabled automatically.';
      return;
    }

    final remainingFailures = (_failuresBeforeOffline - _consecutiveFailures)
        .clamp(0, 99);
    automaticOfflineModeStatus.value = offlineMode.value
        ? 'Connection still appears unavailable'
        : 'Connection check failed. $remainingFailures more failure(s) before offline mode.';
  }

  Future<void> _setOfflineMode(
    bool enabled, {
    required bool autoApplied,
  }) async {
    await addOrUpdateData('settings', _autoAppliedKey, autoApplied);
    await addOrUpdateData('settings', 'offlineMode', enabled);
    automaticOfflineModeApplied.value = autoApplied;
    offlineMode.value = enabled;
    NavigationManager.refreshRouter();
  }

  bool get _autoApplied => automaticOfflineModeApplied.value;
}
