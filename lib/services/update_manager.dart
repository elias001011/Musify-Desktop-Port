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
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:musify/constants/version.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/url_launcher.dart';
import 'package:musify/widgets/auto_format_text.dart';

const String releasesUrl =
    'https://api.github.com/repos/elias001011/Musify-Desktop-Port/releases';
const String mobileReleaseTagPrefix = 'mobile-v';
const String downloadFilename = 'MusifyCloud.apk';
const String downloadArm64Filename = 'MusifyCloud-arm64-v8a.apk';

Future<void> checkAppUpdates() async {
  try {
    final latestRelease = await _fetchLatestMobileCloudRelease();
    if (latestRelease == null) return;

    announcementURL.value = latestRelease['html_url']?.toString();
    final latestVersion = _versionFromRelease(latestRelease);

    if (!isLatestVersionHigher(appVersion, latestVersion)) {
      return;
    }

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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
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
                  child: AutoFormatText(
                    text: latestRelease['body']?.toString() ?? '',
                  ),
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
              onPressed: () {
                getDownloadUrl(latestRelease).then(
                  (url) => {launchURL(Uri.parse(url)), Navigator.pop(context)},
                );
              },
              icon: const Icon(FluentIcons.arrow_download_20_regular),
              label: Text(context.l10n!.download),
            ),
          ],
        );
      },
    );
  } catch (e, stackTrace) {
    logger.log('Error in checkAppUpdates', error: e, stackTrace: stackTrace);
  }
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
              addOrUpdateData('settings', 'shouldWeCheckUpdates', false);
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
              addOrUpdateData('settings', 'shouldWeCheckUpdates', true);
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
  final parsedAppVersion = _parseVersionParts(appVersion);
  final parsedAppLatestVersion = _parseVersionParts(latestVersion);
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

List<int> _parseVersionParts(String version) {
  final match = RegExp(r'(\d+(?:\.\d+){0,3})').firstMatch(version);
  final normalized = match?.group(1) ?? '0';
  return normalized.split('.').map((part) => int.tryParse(part) ?? 0).toList();
}

Future<String> getCPUArchitecture() async {
  final info = await Process.run('uname', ['-m']);
  final cpu = info.stdout.toString().replaceAll('\n', '');

  return cpu;
}

Future<String> getDownloadUrl(Map<String, dynamic> release) async {
  final assets = (release['assets'] as List? ?? [])
      .whereType<Map>()
      .map(Map<String, dynamic>.from)
      .toList();

  String? assetUrl(String name) {
    for (final asset in assets) {
      if (asset['name'] == name) {
        return asset['browser_download_url']?.toString();
      }
    }
    return null;
  }

  var cpuArchitecture = '';
  try {
    cpuArchitecture = await getCPUArchitecture();
  } catch (e, stackTrace) {
    logger.log(
      'Failed to detect CPU architecture',
      error: e,
      stackTrace: stackTrace,
    );
  }

  final preferredNames = cpuArchitecture == 'aarch64'
      ? [downloadArm64Filename, downloadFilename]
      : [downloadFilename, downloadArm64Filename];

  for (final name in preferredNames) {
    final url = assetUrl(name);
    if (url != null && url.isNotEmpty) {
      return url;
    }
  }

  return release['html_url']?.toString() ?? releasesUrl;
}

String _versionFromRelease(Map<String, dynamic> release) {
  final tagName = release['tag_name']?.toString() ?? '';
  final match = RegExp(r'(\d+(?:\.\d+){0,3})').firstMatch(tagName);
  if (match != null) {
    return match.group(1)!;
  }

  return release['name']?.toString() ?? '0.0.0';
}

Future<Map<String, dynamic>?> _fetchLatestMobileCloudRelease() async {
  final releasesRequest = await http.get(Uri.parse(releasesUrl));

  if (releasesRequest.statusCode != 200) {
    logger.log(
      'Fetch update API (releasesUrl) call returned status code ${releasesRequest.statusCode}',
    );
    return null;
  }

  final decoded = json.decode(releasesRequest.body);
  if (decoded is! List) {
    logger.log('Fetch update API (releasesUrl) did not return a list');
    return null;
  }

  for (final rawRelease in decoded) {
    if (rawRelease is! Map) continue;

    final release = Map<String, dynamic>.from(rawRelease);
    final tagName = release['tag_name']?.toString() ?? '';
    final draft = release['draft'] == true;
    final prerelease = release['prerelease'] == true;

    if (!draft && !prerelease && tagName.startsWith(mobileReleaseTagPrefix)) {
      return release;
    }
  }

  return null;
}

/// Fetch only the latest Musify Cloud mobile release URL. This does not trigger
/// update dialogs/downloads and is safe to call for F-Droid builds where update
/// prompts are not allowed.
Future<void> fetchAnnouncementOnly() async {
  try {
    final latestRelease = await _fetchLatestMobileCloudRelease();
    final ann = latestRelease?['html_url'];
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
