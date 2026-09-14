import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/library_merge_service.dart';

Map<String, dynamic> song(String id, [String? title]) => {
  'ytid': id,
  'title': title ?? 'Song $id',
  'artist': 'Artist',
};

Map<String, dynamic> customPlaylist(
  String id,
  String title,
  List<Map<String, dynamic>> songs,
) => {
  'ytid': id,
  'title': title,
  'source': 'user-created',
  'list': songs,
  'createdAt': 1,
};

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('musify_merge_test');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.openBox('user');
    await Hive.openBox('userNoBackup');
    await Hive.openBox('cache');
  });

  setUp(() async {
    await Hive.box('user').clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  /// Serialises through JSON-compatible maps the same way the wire does.
  Map<String, dynamic> roundTrip(Map<String, dynamic> payload) => payload;

  test(
    'export contains every library key and survives a merge round trip',
    () async {
      final user = Hive.box('user');
      await user.put('likedSongs', [song('a'), song('b')]);
      await user.put('playlists', ['PL1']);
      await user.put('recentlyPlayedSongs', [
        {...song('a'), 'listeningCount': 3, 'lastPlayed': DateTime(2026, 1, 1)},
      ]);

      final exported = LibraryMergeService.exportLibrary();
      expect(exported['schemaVersion'], 1);
      expect((exported['likedSongs'] as List).length, 2);
      expect(exported['recentlyPlayedSongs'][0]['lastPlayed'], isA<Map>());

      // Merging our own export back in changes nothing.
      final stats = await LibraryMergeService.mergeLibrary(roundTrip(exported));
      expect(LibraryMergeService.totalAdded(stats), 0);
      expect(
        (user.get('recentlyPlayedSongs') as List)[0]['lastPlayed'],
        isA<DateTime>(),
      );
    },
  );

  test('liked songs, playlists and history are unioned by id', () async {
    final user = Hive.box('user');
    await user.put('likedSongs', [song('a')]);
    await user.put('playlists', ['PL1']);
    await user.put('likedPlaylists', [
      {'ytid': 'LP1', 'title': 'Liked one'},
    ]);
    await user.put('searchHistory', ['rock']);
    await user.put('likedRadioStations', ['r1']);

    final stats = await LibraryMergeService.mergeLibrary({
      'likedSongs': [song('a'), song('b')],
      'playlists': ['PL1', 'PL2'],
      'likedPlaylists': [
        {'ytid': 'LP1', 'title': 'Liked one'},
        {'ytid': 'LP2', 'title': 'Liked two'},
      ],
      'searchHistory': ['rock', 'jazz'],
      'likedRadioStations': ['r1', 'r2'],
    });

    expect(stats['likedSongs'], 1);
    expect(stats['playlists'], 1);
    expect(stats['likedPlaylists'], 1);
    expect(stats['searchHistory'], 1);
    expect(stats['likedRadioStations'], 1);
    expect((user.get('likedSongs') as List).map((s) => s['ytid']), ['a', 'b']);
    expect(user.get('playlists'), ['PL1', 'PL2']);
    expect(user.get('searchHistory'), ['rock', 'jazz']);
  });

  test('custom playlists with the same id merge their songs', () async {
    final user = Hive.box('user');
    await user.put('customPlaylists', [
      customPlaylist('customId-1', 'Mix', [song('a'), song('b')]),
    ]);

    final stats = await LibraryMergeService.mergeLibrary({
      'customPlaylists': [
        customPlaylist('customId-1', 'Mix', [song('b'), song('c')]),
      ],
    });

    expect(stats['customPlaylists'], 0);
    expect(stats['customPlaylistSongs'], 1);
    final merged = (user.get('customPlaylists') as List).single;
    expect((merged['list'] as List).map((s) => s['ytid']), ['a', 'b', 'c']);
  });

  test('same title, different id follows the conflict strategy', () async {
    final user = Hive.box('user');
    final remote = {
      'customPlaylists': [
        customPlaylist('customId-remote', 'Mix', [song('c')]),
      ],
    };

    await user.put('customPlaylists', [
      customPlaylist('customId-local', 'mix', [song('a')]),
    ]);
    await LibraryMergeService.mergeLibrary(remote);
    var playlists = user.get('customPlaylists') as List;
    expect(playlists.length, 1, reason: 'merge folds into the local one');
    expect((playlists.single['list'] as List).length, 2);

    await user.put('customPlaylists', [
      customPlaylist('customId-local', 'Mix', [song('a')]),
    ]);
    await LibraryMergeService.mergeLibrary(
      remote,
      conflictStrategy: PlaylistConflictStrategy.keepBoth,
    );
    playlists = user.get('customPlaylists') as List;
    expect(playlists.length, 2, reason: 'keepBoth adds the remote playlist');

    await user.put('customPlaylists', [
      customPlaylist('customId-local', 'Mix', [song('a'), song('b')]),
    ]);
    await LibraryMergeService.mergeLibrary(
      remote,
      conflictStrategy: PlaylistConflictStrategy.overwrite,
    );
    playlists = user.get('customPlaylists') as List;
    expect(playlists.length, 1);
    expect((playlists.single['list'] as List).map((s) => s['ytid']), [
      'c',
    ], reason: 'overwrite replaces the songs with the incoming list');
  });

  test(
    'playlists inside folders are matched and local placement wins',
    () async {
      final user = Hive.box('user');
      await user.put('customPlaylists', [
        customPlaylist('customId-1', 'Top level here', [song('a')]),
      ]);
      await user.put('playlistFolders', [
        {
          'id': 'f1',
          'name': 'Folder',
          'playlists': [
            customPlaylist('customId-2', 'In folder here', [song('b')]),
          ],
          'createdAt': 1,
        },
      ]);

      final stats = await LibraryMergeService.mergeLibrary({
        'customPlaylists': [
          // Lives in the folder locally; must not be duplicated at top level.
          customPlaylist('customId-2', 'In folder here', [
            song('b'),
            song('c'),
          ]),
        ],
        'playlistFolders': [
          {
            'id': 'f1',
            'name': 'Folder',
            'playlists': [
              // Top level locally; songs merge, placement stays top level.
              customPlaylist('customId-1', 'Top level here', [song('d')]),
              // New on the other device, goes into the matching local folder.
              customPlaylist('customId-3', 'New in folder', [song('e')]),
            ],
          },
          {
            'id': 'f2',
            'name': 'Other folder',
            'playlists': [
              customPlaylist('customId-4', 'New folder playlist', []),
            ],
          },
        ],
      });

      expect(stats['customPlaylists'], 2);
      expect(stats['customPlaylistSongs'], 3);
      expect(stats['playlistFolders'], 1);

      final topLevel = user.get('customPlaylists') as List;
      expect(topLevel.map((p) => p['ytid']), ['customId-1']);
      expect((topLevel.single['list'] as List).map((s) => s['ytid']), [
        'a',
        'd',
      ]);

      final folders = user.get('playlistFolders') as List;
      expect(folders.length, 2);
      final folder1 = folders.firstWhere((f) => f['id'] == 'f1');
      expect((folder1['playlists'] as List).map((p) => p['ytid']), [
        'customId-2',
        'customId-3',
      ]);
      final folder2 = folders.firstWhere((f) => f['id'] == 'f2');
      expect((folder2['playlists'] as List).map((p) => p['ytid']), [
        'customId-4',
      ]);
    },
  );

  test('recently played keeps the latest play and the higher count', () async {
    final user = Hive.box('user');
    await user.put('recentlyPlayedSongs', [
      {...song('a'), 'listeningCount': 5, 'lastPlayed': DateTime(2026, 1, 1)},
      {...song('b'), 'listeningCount': 1, 'lastPlayed': DateTime(2026, 1, 3)},
    ]);

    final stats = await LibraryMergeService.mergeLibrary({
      'recentlyPlayedSongs': [
        {
          ...song('a'),
          'listeningCount': 2,
          'lastPlayed': {
            '__musifyType': 'DateTime',
            'value': DateTime.utc(2026, 1, 5).toIso8601String(),
          },
        },
        {
          ...song('c'),
          'listeningCount': 1,
          'lastPlayed': {
            '__musifyType': 'DateTime',
            'value': DateTime.utc(2026, 1, 2).toIso8601String(),
          },
        },
      ],
    });

    expect(stats['recentlyPlayedSongs'], 1);
    final result = user.get('recentlyPlayedSongs') as List;
    expect(result.map((s) => s['ytid']), ['a', 'b', 'c']);
    expect(result[0]['listeningCount'], 5);
    expect(
      (result[0]['lastPlayed'] as DateTime).toUtc(),
      DateTime.utc(2026, 1, 5),
    );
  });

  test('pinned playlists respect the limit', () async {
    final user = Hive.box('user');
    await user.put('pinnedPlaylistIds', ['p1', 'p2', 'p3', 'p4']);

    final stats = await LibraryMergeService.mergeLibrary({
      'pinnedPlaylistIds': ['p5', 'p6', 'p7'],
    });

    expect(stats['pinnedPlaylistIds'], 1);
    expect(user.get('pinnedPlaylistIds'), ['p1', 'p2', 'p3', 'p4', 'p5']);
  });
}
