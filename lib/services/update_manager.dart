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

import 'dart:convert';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/version.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/url_launcher.dart';
import 'package:musify/widgets/auto_format_text.dart';

const String checkUrl =
    'https://raw.githubusercontent.com/gokadzev/Musify/update/check.json';
const String releasesUrl =
    'https://api.github.com/repos/gokadzev/Musify/releases/latest';
const String desktopReleasesUrl =
    'https://api.github.com/repos/elias001011/Musify-Desktop-Port/releases';
const String desktopReleaseTagPrefix = 'desktop-v';
const String desktopBuildReleaseTag = String.fromEnvironment(
  'MUSIFY_DESKTOP_RELEASE_TAG',
);
const String downloadUrlKey = 'url';
const String downloadUrlArm64Key = 'arm64url';
const String downloadFilename = 'Musify.apk';

bool get _checksDesktopReleases =>
    !kIsWeb && (Platform.isLinux || Platform.isWindows);

Future<void> checkAppUpdates() async {
  try {
    if (_checksDesktopReleases) {
      await _checkDesktopAppUpdates();
    } else {
      await _checkAndroidAppUpdates();
    }
  } catch (e, stackTrace) {
    logger.log('Error in checkAppUpdates', error: e, stackTrace: stackTrace);
  }
}

Future<void> _checkAndroidAppUpdates() async {
  final response = await http.get(Uri.parse(checkUrl));

  if (response.statusCode != 200) {
    logger.log(
      'Fetch update API (checkUrl) call returned status code ${response.statusCode}',
    );
    return;
  }

  final map = json.decode(response.body) as Map<String, dynamic>;
  announcementURL.value = map['announcementurl'];
  final latestVersion = map['version'].toString();

  if (!isLatestVersionHigher(appVersion, latestVersion)) {
    return;
  }

  final releasesRequest = await http.get(Uri.parse(releasesUrl));

  if (releasesRequest.statusCode != 200) {
    logger.log(
      'Fetch update API (releasesUrl) call returned status code ${releasesRequest.statusCode}',
    );
    return;
  }

  final releasesResponse =
      json.decode(releasesRequest.body) as Map<String, dynamic>;

  await _showUpdateDialog(
    latestVersion: latestVersion,
    releaseBody: releasesResponse['body']?.toString() ?? '',
    resolveDownloadUrl: () => getDownloadUrl(map),
  );
}

Future<void> _checkDesktopAppUpdates() async {
  final releasesRequest = await http.get(
    Uri.parse(desktopReleasesUrl),
    headers: const {'Accept': 'application/vnd.github+json'},
  );

  if (releasesRequest.statusCode != 200) {
    logger.log(
      'Fetch update API (desktopReleasesUrl) call returned status code ${releasesRequest.statusCode}',
    );
    return;
  }

  final decoded = json.decode(releasesRequest.body);
  if (decoded is! List) {
    logger.log('Fetch update API (desktopReleasesUrl) did not return a list');
    return;
  }

  final release = _latestDesktopRelease(decoded);
  if (release == null) {
    return;
  }

  final latestTag = release['tag_name']?.toString() ?? '';
  final latestVersion = _desktopVersionFromTag(latestTag);
  final installedVersion = await _installedDesktopVersion();

  if (!isLatestVersionHigher(installedVersion, latestVersion)) {
    return;
  }

  await _showUpdateDialog(
    latestVersion: latestVersion,
    releaseBody: release['body']?.toString() ?? '',
    resolveDownloadUrl: () async => getDesktopDownloadUrl(release),
  );
}

Future<void> _showUpdateDialog({
  required String latestVersion,
  required String releaseBody,
  required Future<String> Function() resolveDownloadUrl,
}) async {
  await showDialog(
    context: NavigationManager().context,
    builder: (BuildContext context) {
      final colorScheme = Theme.of(context).colorScheme;

      return AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                FluentIcons.arrow_download_24_regular,
                color: colorScheme.onPrimaryContainer,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n!.appUpdateIsAvailable,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'V$latestVersion',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height / 2.5,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SingleChildScrollView(
                child: AutoFormatText(text: releaseBody),
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: <Widget>[
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colorScheme.outline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(context.l10n!.cancel),
          ),
          FilledButton.icon(
            onPressed: () async {
              final url = await resolveDownloadUrl();
              await launchURL(Uri.parse(url));
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            icon: const Icon(FluentIcons.arrow_download_20_regular),
            label: Text(context.l10n!.download),
          ),
        ],
      );
    },
  );
}

void showUpdateCheckDialog(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        icon: Icon(
          FluentIcons.arrow_sync_circle_24_regular,
          color: colorScheme.primary,
          size: 40,
        ),
        title: Text(
          context.l10n!.checkForUpdates,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        content: Text(
          context.l10n!.enableUpdateChecksDescription,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            onPressed: () {
              shouldWeCheckUpdates.value = false;
              addOrUpdateData<bool>('settings', 'shouldWeCheckUpdates', false);
              Navigator.of(context).pop();
            },
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colorScheme.outline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(context.l10n!.no),
          ),
          FilledButton(
            onPressed: () {
              shouldWeCheckUpdates.value = true;
              addOrUpdateData<bool>('settings', 'shouldWeCheckUpdates', true);
              if (!isFdroidBuild && kReleaseMode && !offlineMode.value) {
                checkAppUpdates();
                isUpdateChecked = true;
              }
              Navigator.of(context).pop();
            },
            child: Text(context.l10n!.yes),
          ),
        ],
      );
    },
  );
}

bool isLatestVersionHigher(String appVersion, String latestVersion) {
  final parsedAppVersion = _versionParts(appVersion);
  final parsedAppLatestVersion = _versionParts(latestVersion);
  final length = parsedAppVersion.length > parsedAppLatestVersion.length
      ? parsedAppVersion.length
      : parsedAppLatestVersion.length;

  for (var i = 0; i < length; i++) {
    final value1 = i < parsedAppVersion.length ? parsedAppVersion[i] : 0;
    final value2 = i < parsedAppLatestVersion.length
        ? parsedAppLatestVersion[i]
        : 0;
    if (value2 > value1) {
      return true;
    } else if (value2 < value1) {
      return false;
    }
  }

  return false;
}

List<int> _versionParts(String version) {
  return RegExp(
    r'\d+',
  ).allMatches(version).map((match) => int.parse(match.group(0)!)).toList();
}

Future<String> getCPUArchitecture() async {
  final info = await Process.run('uname', ['-m']);
  final cpu = info.stdout.toString().replaceAll('\n', '');

  return cpu;
}

Future<String> getDownloadUrl(Map<String, dynamic> map) async {
  final cpuArchitecture = await getCPUArchitecture();
  final url = cpuArchitecture == 'aarch64'
      ? map[downloadUrlArm64Key].toString()
      : map[downloadUrlKey].toString();

  return url;
}

String _desktopVersionFromTag(String tag) {
  return tag
      .replaceFirst(RegExp('^$desktopReleaseTagPrefix'), '')
      .replaceFirst(RegExp('^v'), '');
}

Map<String, dynamic>? _latestDesktopRelease(List<dynamic> releases) {
  for (final rawRelease in releases) {
    if (rawRelease is! Map) continue;

    final release = Map<String, dynamic>.from(rawRelease);
    final tagName = release['tag_name']?.toString() ?? '';
    final draft = release['draft'] == true;
    final prerelease = release['prerelease'] == true;

    if (!draft && !prerelease && tagName.startsWith(desktopReleaseTagPrefix)) {
      return release;
    }
  }

  return null;
}

Future<String> _installedDesktopVersion() async {
  if (desktopBuildReleaseTag.isNotEmpty) {
    return _desktopVersionFromTag(desktopBuildReleaseTag);
  }

  final linuxPackageVersion = await _linuxPackageVersion();
  if (linuxPackageVersion != null) {
    return linuxPackageVersion;
  }

  return appVersion;
}

Future<String?> _linuxPackageVersion() async {
  if (kIsWeb || !Platform.isLinux) {
    return null;
  }

  try {
    final result = await Process.run('dpkg-query', [
      '-W',
      '-f=\${Version}',
      'musify',
    ]);
    final version = result.stdout.toString().trim();
    if (result.exitCode == 0 && version.isNotEmpty) {
      return version;
    }
  } catch (e, stackTrace) {
    logger.log(
      'Failed to read installed Linux package version',
      error: e,
      stackTrace: stackTrace,
    );
  }

  return null;
}

String getDesktopDownloadUrl(Map<String, dynamic> release) {
  final assets = (release['assets'] as List<dynamic>? ?? [])
      .cast<Map<String, dynamic>>();
  final preferredAssetNames = Platform.isWindows
      ? const [
          'Musify-windows-x64-setup.exe',
          'Musify-windows-x64-portable.zip',
        ]
      : const ['Musify-linux-x64.deb', 'Musify-linux-x64.tar.gz'];

  for (final name in preferredAssetNames) {
    final asset = assets.firstWhere(
      (asset) => asset['name'] == name,
      orElse: () => <String, dynamic>{},
    );
    final downloadUrl = asset['browser_download_url']?.toString();
    if (downloadUrl != null && downloadUrl.isNotEmpty) {
      return downloadUrl;
    }
  }

  return release['html_url'].toString();
}

/// Fetch only the announcement URL from the `check.json` file and set the
/// global `announcementURL` ValueNotifier. This does not trigger releases
/// fetching or any update dialogs/downloads and is safe to call for F‑Droid
/// builds where update prompts are not allowed.
Future<void> fetchAnnouncementOnly() async {
  try {
    final response = await http.get(Uri.parse(checkUrl));

    if (response.statusCode != 200) {
      logger.log(
        'Fetch announcement (checkUrl) call returned status code ${response.statusCode}',
      );
      return;
    }

    final map = json.decode(response.body) as Map<String, dynamic>;
    final ann = map['announcementurl'];
    if (ann != null) {
      announcementURL.value = ann.toString();
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error in fetchAnnouncementOnly',
      error: e,
      stackTrace: stackTrace,
    );
  }
}
