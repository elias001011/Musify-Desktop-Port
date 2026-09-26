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

late String applicationDirPath;

/// Root of the downloaded songs (`tracks/`) and their artworks (`artworks/`).
/// It is [applicationDirPath] unless the user picked another folder on
/// desktop (see `downloads_location_service.dart`).
late String downloadsDirPath;

class FilePaths {
  // File extensions
  static const String audioExtension = '.m4a';
  static const String artworkExtension = '.jpg';

  // Directory names
  static const String tracksDir = 'tracks';
  static const String artworksDir = 'artworks';
  static const String streamBufferDir = 'stream_buffer';

  // Get full paths for various file types
  static String getAudioPath(String songId) {
    return '$downloadsDirPath/$tracksDir/$songId$audioExtension';
  }

  static String getArtworkPath(String songId) {
    return '$downloadsDirPath/$artworksDir/$songId$artworkExtension';
  }

  // Holds the song being played while it downloads. Temporary, unlike the
  // songs the user deliberately downloaded into tracksDir.
  static String getStreamBufferDirPath() {
    return '$applicationDirPath/$streamBufferDir';
  }

  /// Whether [path] names a file Musify downloaded into [tracksDir] or
  /// [artworksDir]: a YouTube id plus the matching extension. A custom
  /// downloads folder may hold the user's own files next to ours, and those
  /// must never be moved or deleted along with the downloads.
  static bool isDownloadedFile(String path, {required bool artwork}) {
    final name = path.split(Platform.pathSeparator).last.split('/').last;
    final extension = artwork ? artworkExtension : audioExtension;
    if (!name.endsWith(extension)) return false;
    final id = name.substring(0, name.length - extension.length);
    return _youtubeIdPattern.hasMatch(id);
  }

  static final _youtubeIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// Deletes every download: the files [offlineSongs] point at, wherever
  /// they are, and whatever else of ours is left in the download folders.
  /// Only Musify's own files go, since a custom downloads folder may hold the
  /// user's files as well.
  static Future<void> deleteDownloadedFiles(List offlineSongs) async {
    final paths = <String>{
      for (final song in offlineSongs)
        if (song is Map) ...[
          if (song['audioPath'] case final String path) path,
          if (song['artworkPath'] case final String path) path,
        ],
    };

    for (final artwork in [false, true]) {
      final directory = Directory(
        '$downloadsDirPath/${artwork ? artworksDir : tracksDir}',
      );
      if (!await directory.exists()) continue;
      await for (final entity in directory.list()) {
        if (entity is File && isDownloadedFile(entity.path, artwork: artwork)) {
          paths.add(entity.path);
        }
      }
    }

    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  // Ensure directories exist
  static Future<void> ensureDirectoriesExist() async {
    final tracksDirectory = Directory('$downloadsDirPath/$tracksDir');
    final artworksDirectory = Directory('$downloadsDirPath/$artworksDir');

    if (!await tracksDirectory.exists()) {
      await tracksDirectory.create(recursive: true);
    }

    if (!await artworksDirectory.exists()) {
      await artworksDirectory.create(recursive: true);
    }

    final streamBufferDirectory = Directory(getStreamBufferDirPath());
    if (!await streamBufferDirectory.exists()) {
      await streamBufferDirectory.create(recursive: true);
    }
  }
}
