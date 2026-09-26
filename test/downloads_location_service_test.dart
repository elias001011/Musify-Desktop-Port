import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/downloads_location_service.dart';
import 'package:musify/services/io_service.dart';
import 'package:musify/services/playlist_download_service.dart';

void main() {
  late Directory tempDir;
  late String defaultRoot;
  late String customRoot;

  const songId = 'dQw4w9WgXcQ';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('musify_downloads_test');
    Hive.init('${tempDir.path}/hive');
    await Hive.openBox('settings');
    await Hive.openBox('user');
    await Hive.openBox('userNoBackup');
    await Hive.openBox('cache');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    defaultRoot = '${tempDir.path}/default';
    customRoot = '${tempDir.path}/custom';
    for (final root in [defaultRoot, customRoot]) {
      final directory = Directory(root);
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
    await Hive.box('userNoBackup').clear();

    applicationDirPath = defaultRoot;
    await DownloadsLocation.initialise();
    await FilePaths.ensureDirectoriesExist();

    await File(FilePaths.getAudioPath(songId)).writeAsString('audio');
    await File(FilePaths.getArtworkPath(songId)).writeAsString('artwork');
    // Not ours: must stay where it is.
    await File('$defaultRoot/tracks/my song.m4a').writeAsString('mine');

    final song = {
      'ytid': songId,
      'audioPath': FilePaths.getAudioPath(songId),
      'artworkPath': FilePaths.getArtworkPath(songId),
    };
    userOfflineSongs.value = [song];
    offlinePlaylistService.offlinePlaylists.value = [
      {
        'ytid': 'playlist',
        'list': [Map.of(song)],
      },
    ];
  });

  test('moves downloads and rewrites the stored paths', () async {
    final status = await DownloadsLocation.change(customRoot);

    expect(status, DownloadsMoveStatus.moved);
    expect(downloadsDirPath, customRoot);
    expect(DownloadsLocation.customPath, customRoot);

    final audio = '$customRoot/tracks/$songId.m4a';
    final artwork = '$customRoot/artworks/$songId.jpg';
    expect(File(audio).readAsStringSync(), 'audio');
    expect(File(artwork).readAsStringSync(), 'artwork');
    expect(File('$defaultRoot/tracks/$songId.m4a').existsSync(), isFalse);
    expect(File('$defaultRoot/tracks/my song.m4a').existsSync(), isTrue);

    expect(userOfflineSongs.value.single['audioPath'], audio);
    expect(userOfflineSongs.value.single['artworkPath'], artwork);
    final playlistSong =
        (offlinePlaylistService.offlinePlaylists.value.single as Map)['list']
            .single;
    expect(playlistSong['audioPath'], audio);
  });

  test('moving back to the default forgets the custom folder', () async {
    await DownloadsLocation.change(customRoot);
    final status = await DownloadsLocation.change(null);

    expect(status, DownloadsMoveStatus.moved);
    expect(downloadsDirPath, defaultRoot);
    expect(DownloadsLocation.customPath, isNull);
    expect(
      userOfflineSongs.value.single['audioPath'],
      '$defaultRoot/tracks/$songId.m4a',
    );
    expect(Directory('$customRoot/tracks').existsSync(), isFalse);
  });

  test('a missing custom folder falls back to the default', () async {
    await DownloadsLocation.change(customRoot);
    Directory(customRoot).deleteSync(recursive: true);

    await DownloadsLocation.initialise();

    expect(DownloadsLocation.unavailable, isTrue);
    expect(downloadsDirPath, defaultRoot);
    expect(DownloadsLocation.customPath, customRoot);
    expect(Directory(customRoot).existsSync(), isFalse);
  });

  test('an unwritable folder changes nothing', () async {
    final blocker = File('${tempDir.path}/not-a-folder');
    await blocker.writeAsString('x');

    final status = await DownloadsLocation.change(blocker.path);

    expect(status, DownloadsMoveStatus.notWritable);
    expect(downloadsDirPath, defaultRoot);
    expect(File(FilePaths.getAudioPath(songId)).existsSync(), isTrue);
  });

  test('deleting all downloads leaves foreign files alone', () async {
    await FilePaths.deleteDownloadedFiles(userOfflineSongs.value);

    expect(File('$defaultRoot/tracks/$songId.m4a').existsSync(), isFalse);
    expect(File('$defaultRoot/artworks/$songId.jpg').existsSync(), isFalse);
    expect(File('$defaultRoot/tracks/my song.m4a').existsSync(), isTrue);
  });
}
