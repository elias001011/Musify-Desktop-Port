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

import 'dart:io';

import 'package:hive/hive.dart';
import 'package:musify/main.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/io_service.dart';
import 'package:musify/services/playlist_download_service.dart';
import 'package:musify/utilities/platform_utils.dart';

/// Outcome of moving the downloads to another folder.
enum DownloadsMoveStatus {
  /// Everything was moved and the new folder is in use.
  moved,

  /// The new folder is in use, but some files could not be moved and still
  /// play from where they were.
  partiallyMoved,

  /// The folder could not be created or written to. Nothing changed.
  notWritable,
}

/// The desktop downloads folder. Changing it moves the files and rewrites the
/// stored paths. Kept in `userNoBackup`: it is a path on this machine only.
class DownloadsLocation {
  DownloadsLocation._();

  static const _storageKey = 'downloadsDirectory';

  /// The chosen folder was missing at startup (an unplugged drive); downloads
  /// use the default folder meanwhile, and the setting is kept.
  static bool unavailable = false;

  static String? get customPath {
    final value = Hive.box('userNoBackup').get(_storageKey);
    return value is String && value.isNotEmpty ? value : null;
  }

  static String get defaultPath => applicationDirPath;

  /// Resolves [downloadsDirPath]. Must run after [applicationDirPath] is set.
  static Future<void> initialise() async {
    downloadsDirPath = defaultPath;
    if (!isDesktopPlatform) return;

    final custom = customPath;
    if (custom == null) return;

    // Never recreated: it could fill the mount point of an unplugged drive.
    if (await Directory(custom).exists()) {
      downloadsDirPath = custom;
      unavailable = false;
    } else {
      unavailable = true;
      logger.log('Downloads folder $custom is unavailable, using the default');
    }
  }

  /// Moves the downloads to [newRoot], or back to the default when null.
  static Future<DownloadsMoveStatus> change(String? newRoot) async {
    if (!isDesktopPlatform)
      throw UnsupportedError('Custom download folders are desktop only');
    final target = _trimSeparator(newRoot ?? defaultPath);

    if (!await _prepare(target)) return DownloadsMoveStatus.notWritable;

    var failed = 0;
    final sources = <String>{downloadsDirPath, defaultPath, ?customPath}
      ..remove(target);

    for (final source in sources) {
      failed += await _moveFolderContents(source, target);
    }

    // Copied, not moved: files outside our folders, such as an older
    // documents directory, may still belong to another Musify install.
    for (final song in userOfflineSongs.value) {
      if (song is! Map) continue;
      failed += await _copyReferencedFile(song['audioPath'], target, false);
      failed += await _copyReferencedFile(song['artworkPath'], target, true);
    }

    _rewriteStoredPaths(target);

    if (target == _trimSeparator(defaultPath)) {
      await deleteData('userNoBackup', _storageKey);
    } else {
      await addOrUpdateData<String>('userNoBackup', _storageKey, target);
    }
    downloadsDirPath = target;
    unavailable = false;

    for (final source in sources) {
      if (source != defaultPath) await _removeIfEmpty(source);
    }

    return failed == 0
        ? DownloadsMoveStatus.moved
        : DownloadsMoveStatus.partiallyMoved;
  }

  static Future<bool> _prepare(String root) async {
    try {
      await Directory('$root/${FilePaths.tracksDir}').create(recursive: true);
      await Directory('$root/${FilePaths.artworksDir}').create(recursive: true);

      final probe = File('$root/${FilePaths.tracksDir}/.musify-write-test');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (e, stackTrace) {
      logger.log(
        'Downloads folder $root is not writable',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Returns how many files could not be moved.
  static Future<int> _moveFolderContents(String source, String target) async {
    var failed = 0;
    for (final artwork in [false, true]) {
      final subDir = artwork ? FilePaths.artworksDir : FilePaths.tracksDir;
      final directory = Directory('$source/$subDir');
      if (!await directory.exists()) continue;

      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        if (!FilePaths.isDownloadedFile(entity.path, artwork: artwork)) {
          continue;
        }
        final name = entity.uri.pathSegments.last;
        if (!await _moveFile(entity, '$target/$subDir/$name')) failed++;
      }
    }
    return failed;
  }

  static Future<int> _copyReferencedFile(
    Object? path,
    String target,
    bool artwork,
  ) async {
    if (path is! String || path.isEmpty) return 0;
    final file = File(path);
    if (!await file.exists()) return 0;

    final subDir = artwork ? FilePaths.artworksDir : FilePaths.tracksDir;
    final destination = '$target/$subDir/${file.uri.pathSegments.last}';
    if (destination == path || await File(destination).exists()) return 0;
    try {
      await file.copy(destination);
      return 0;
    } catch (e, stackTrace) {
      logger.log(
        'Could not copy $path to $destination',
        error: e,
        stackTrace: stackTrace,
      );
      return 1;
    }
  }

  static Future<bool> _moveFile(File file, String destination) async {
    try {
      if (await File(destination).exists()) {
        // Same song id, already there: keep one copy, not two.
        await file.delete();
        return true;
      }
      try {
        await file.rename(destination);
      } on FileSystemException {
        // rename() can't cross drives: copy, then delete the original.
        await file.copy(destination);
        await file.delete();
      }
      return true;
    } catch (e, stackTrace) {
      logger.log(
        'Could not move ${file.path} to $destination',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Songs whose file did not move keep the path that still works.
  static void _rewriteStoredPaths(String root) {
    Map rewrite(Map song) {
      final updated = Map<String, dynamic>.from(song);
      for (final (key, subDir) in [
        ('audioPath', FilePaths.tracksDir),
        ('artworkPath', FilePaths.artworksDir),
      ]) {
        final path = updated[key];
        if (path is! String || path.isEmpty) continue;
        final moved = '$root/$subDir/${File(path).uri.pathSegments.last}';
        if (File(moved).existsSync()) updated[key] = moved;
      }
      return updated;
    }

    userOfflineSongs.value = [
      for (final song in userOfflineSongs.value)
        if (song is Map) rewrite(song) else song,
    ];
    addOrUpdateData<List>(
      'userNoBackup',
      'offlineSongs',
      userOfflineSongs.value,
    );

    final playlists = offlinePlaylistService.offlinePlaylists;
    playlists.value = [
      for (final playlist in playlists.value)
        if (playlist is Map && playlist['list'] is List)
          {
            ...Map<String, dynamic>.from(playlist),
            'list': [
              for (final song in playlist['list'] as List)
                if (song is Map) rewrite(song) else song,
            ],
          }
        else
          playlist,
    ];
    addOrUpdateData<List>('userNoBackup', 'offlinePlaylists', playlists.value);
  }

  static Future<void> _removeIfEmpty(String root) async {
    for (final subDir in [FilePaths.tracksDir, FilePaths.artworksDir]) {
      try {
        final directory = Directory('$root/$subDir');
        if (await directory.exists() && await directory.list().isEmpty) {
          await directory.delete();
        }
      } catch (_) {
        // Left in place: an empty folder is harmless.
      }
    }
  }

  static String _trimSeparator(String path) {
    var result = path;
    while (result.length > 1 &&
        (result.endsWith('/') || result.endsWith(r'\'))) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
