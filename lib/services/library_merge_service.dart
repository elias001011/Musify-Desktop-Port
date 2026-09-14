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

import 'package:hive/hive.dart';
import 'package:musify/screens/search_page.dart';
import 'package:musify/services/backed_up_state_manager.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/playlists_manager.dart';

/// What to do when both devices hold a custom playlist with the same title but
/// a different id (a playlist created separately on each device).
///
/// A playlist that shares its id on both devices is always the same playlist
/// and its songs are merged regardless of the strategy.
enum PlaylistConflictStrategy { merge, keepBoth, overwrite }

/// Builds the library payload exchanged between two devices and merges an
/// incoming payload into local storage.
///
/// The merge is additive: songs, playlists and folders present on the other
/// device are added here, nothing is removed. That keeps a sync safe to run
/// in either direction and at any time, at the cost of deletions not
/// propagating between devices.
class LibraryMergeService {
  LibraryMergeService._();

  static const int schemaVersion = 1;

  static const String _dateTimeMarker = '__musifyType';

  /// Storage keys in the `user` box that take part in a sync.
  static const List<String> libraryKeys = [
    'likedSongs',
    'likedRadioStations',
    'playlists',
    'likedPlaylists',
    'customPlaylists',
    'playlistFolders',
    'pinnedPlaylistIds',
    'recentlyPlayedSongs',
    'searchHistory',
  ];

  /// Serialises the local library as a JSON-compatible map.
  static Map<String, dynamic> exportLibrary() {
    final box = Hive.box('user');
    return {
      'schemaVersion': schemaVersion,
      for (final key in libraryKeys)
        key: _encodeValue(box.get(key, defaultValue: const [])),
    };
  }

  /// Merges [remote] into the local library and returns how many items were
  /// added, keyed by category. Only touches storage keys that actually changed.
  static Future<Map<String, int>> mergeLibrary(
    Map<String, dynamic> remote, {
    PlaylistConflictStrategy conflictStrategy = PlaylistConflictStrategy.merge,
  }) async {
    final box = Hive.box('user');
    final stats = <String, int>{};
    var changed = false;

    Future<void> store(String key, dynamic value) async {
      await box.put(key, value);
      changed = true;
    }

    // Liked songs: newest first locally, so remote-only songs go to the end.
    final likedSongs = _mergeMapListById(
      _mapList(box.get('likedSongs')),
      _mapList(_decodeValue(remote['likedSongs'])),
    );
    stats['likedSongs'] = likedSongs.added;
    if (likedSongs.added > 0) await store('likedSongs', likedSongs.result);

    final radioStations = _mergeStringList(
      _stringList(box.get('likedRadioStations')),
      _stringList(remote['likedRadioStations']),
    );
    stats['likedRadioStations'] = radioStations.added;
    if (radioStations.added > 0) {
      await store('likedRadioStations', radioStations.result);
    }

    final playlists = _mergeStringList(
      _stringList(box.get('playlists')),
      _stringList(remote['playlists']),
    );
    stats['playlists'] = playlists.added;
    if (playlists.added > 0) await store('playlists', playlists.result);

    final likedPlaylists = _mergeMapListById(
      _mapList(box.get('likedPlaylists')),
      _mapList(_decodeValue(remote['likedPlaylists'])),
    );
    stats['likedPlaylists'] = likedPlaylists.added;
    if (likedPlaylists.added > 0) {
      await store('likedPlaylists', likedPlaylists.result);
    }

    final custom = _mergeCustomPlaylists(
      localTopLevel: _mapList(box.get('customPlaylists')),
      localFolders: _mapList(box.get('playlistFolders')),
      remoteTopLevel: _mapList(_decodeValue(remote['customPlaylists'])),
      remoteFolders: _mapList(_decodeValue(remote['playlistFolders'])),
      strategy: conflictStrategy,
    );
    stats['customPlaylists'] = custom.playlistsAdded;
    stats['customPlaylistSongs'] = custom.songsAdded;
    stats['playlistFolders'] = custom.foldersAdded;
    if (custom.changed) {
      await store('customPlaylists', custom.topLevel);
      await store('playlistFolders', custom.folders);
    }

    final pinned = _mergeStringList(
      _stringList(box.get('pinnedPlaylistIds')),
      _stringList(remote['pinnedPlaylistIds']),
      limit: pinnedPlaylistsLimit,
    );
    stats['pinnedPlaylistIds'] = pinned.added;
    if (pinned.added > 0) await store('pinnedPlaylistIds', pinned.result);

    final recentlyPlayed = _mergeRecentlyPlayed(
      _mapList(box.get('recentlyPlayedSongs')),
      _mapList(_decodeValue(remote['recentlyPlayedSongs'])),
    );
    stats['recentlyPlayedSongs'] = recentlyPlayed.added;
    if (recentlyPlayed.changed) {
      await store('recentlyPlayedSongs', recentlyPlayed.result);
    }

    final searchHistory = _mergeStringList(
      _stringList(box.get('searchHistory')),
      _stringList(remote['searchHistory']),
    );
    stats['searchHistory'] = searchHistory.added;
    if (searchHistory.added > 0) {
      await store('searchHistory', searchHistory.result);
    }

    if (changed) {
      refreshBackedUpStateFromStorage();
      reloadSearchHistoryFromStorage();
    }

    return stats;
  }

  /// Total number of items a merge added, for status messages.
  static int totalAdded(Map<String, int> stats) =>
      stats.values.fold(0, (sum, value) => sum + value);

  // ---------------------------------------------------------------------------
  // Simple lists
  // ---------------------------------------------------------------------------

  static ({List<String> result, int added}) _mergeStringList(
    List<String> local,
    List<String> remote, {
    int? limit,
  }) {
    final result = List<String>.from(local);
    final seen = local.toSet();
    var added = 0;
    for (final value in remote) {
      if (limit != null && result.length >= limit) break;
      if (seen.add(value)) {
        result.add(value);
        added++;
      }
    }
    return (result: result, added: added);
  }

  static ({List<Map> result, int added}) _mergeMapListById(
    List<Map> local,
    List<Map> remote,
  ) {
    final result = List<Map>.from(local);
    final seen = local.map(_idOf).whereType<String>().toSet();
    var added = 0;
    for (final item in remote) {
      final id = _idOf(item);
      if (id == null || !seen.add(id)) continue;
      result.add(Map<String, dynamic>.from(item));
      added++;
    }
    return (result: result, added: added);
  }

  static ({List<Map> result, int added, bool changed}) _mergeRecentlyPlayed(
    List<Map> local,
    List<Map> remote,
  ) {
    final byId = <String, Map>{};
    for (final item in local) {
      final id = _idOf(item);
      if (id != null) byId[id] = Map<String, dynamic>.from(item);
    }

    var added = 0;
    var changed = false;
    for (final item in remote) {
      final id = _idOf(item);
      if (id == null) continue;
      final existing = byId[id];
      if (existing == null) {
        byId[id] = Map<String, dynamic>.from(item);
        added++;
        changed = true;
        continue;
      }

      // Both devices played this song: keep the most recent play and the
      // higher play count rather than summing, since both counts include the
      // plays that were already synced before.
      final remotePlayed = _dateOf(item['lastPlayed']);
      final localPlayed = _dateOf(existing['lastPlayed']);
      if (remotePlayed != null &&
          (localPlayed == null || remotePlayed.isAfter(localPlayed))) {
        existing['lastPlayed'] = remotePlayed;
        changed = true;
      }
      final remoteCount = _intOf(item['listeningCount']);
      if (remoteCount > _intOf(existing['listeningCount'])) {
        existing['listeningCount'] = remoteCount;
        changed = true;
      }
    }

    final result = byId.values.toList()
      ..sort((a, b) {
        final aDate = _dateOf(a['lastPlayed']);
        final bDate = _dateOf(b['lastPlayed']);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

    if (result.length > recentlyPlayedSongsLimit) {
      result.removeRange(recentlyPlayedSongsLimit, result.length);
      changed = true;
    }

    return (result: result, added: added, changed: changed);
  }

  // ---------------------------------------------------------------------------
  // Custom playlists and folders
  // ---------------------------------------------------------------------------

  /// A custom playlist can live at the top level or inside a folder. Both
  /// devices may place the same playlist differently, so playlists are
  /// matched wherever they are and the local placement always wins.
  static ({
    List<Map> topLevel,
    List<Map> folders,
    int playlistsAdded,
    int songsAdded,
    int foldersAdded,
    bool changed,
  })
  _mergeCustomPlaylists({
    required List<Map> localTopLevel,
    required List<Map> localFolders,
    required List<Map> remoteTopLevel,
    required List<Map> remoteFolders,
    required PlaylistConflictStrategy strategy,
  }) {
    final topLevel = localTopLevel.map(Map<String, dynamic>.from).toList();
    final folders = localFolders.map((folder) {
      final copy = Map<String, dynamic>.from(folder);
      copy['playlists'] = _mapList(folder['playlists'])
          .map(Map<String, dynamic>.from)
          .toList();
      return copy;
    }).toList();

    final localById = <String, Map>{};
    final localByTitle = <String, Map>{};
    void index(Map playlist) {
      final id = _idOf(playlist);
      if (id != null) localById[id] = playlist;
      final title = _titleKey(playlist);
      if (title != null) localByTitle.putIfAbsent(title, () => playlist);
    }

    topLevel.forEach(index);
    for (final folder in folders) {
      for (final playlist in folder['playlists'] as List<Map>) {
        index(playlist);
      }
    }

    var playlistsAdded = 0;
    var songsAdded = 0;
    var foldersAdded = 0;
    var changed = false;

    void mergeInto(Map local, Map remote) {
      final localSongs = _mapList(local['list']);
      final remoteSongs = _mapList(remote['list']);

      if (strategy == PlaylistConflictStrategy.overwrite) {
        final localIds = localSongs.map(_idOf).whereType<String>().toSet();
        final remoteIds = remoteSongs.map(_idOf).whereType<String>().toSet();
        if (localIds.length != remoteIds.length ||
            !localIds.containsAll(remoteIds) ||
            !_sameOrder(localSongs, remoteSongs)) {
          local['list'] = remoteSongs.map(Map<String, dynamic>.from).toList();
          songsAdded += remoteIds.difference(localIds).length;
          changed = true;
        }
        return;
      }

      final merged = _mergeMapListById(localSongs, remoteSongs);
      if (merged.added > 0) {
        local['list'] = merged.result;
        songsAdded += merged.added;
        changed = true;
      }
    }

    Map? findMatch(Map remote) {
      final id = _idOf(remote);
      if (id != null && localById.containsKey(id)) return localById[id];
      if (strategy == PlaylistConflictStrategy.keepBoth) return null;
      final title = _titleKey(remote);
      return title == null ? null : localByTitle[title];
    }

    /// Adds a playlist that does not exist locally. [remoteFolder] is the
    /// folder it lives in on the other device, if any.
    void addPlaylist(Map remote, Map? remoteFolder) {
      final copy = Map<String, dynamic>.from(remote);
      copy['list'] = _mapList(remote['list'])
          .map(Map<String, dynamic>.from)
          .toList();
      index(copy);
      playlistsAdded++;
      songsAdded += (copy['list'] as List).length;
      changed = true;

      if (remoteFolder == null) {
        topLevel.add(copy);
        return;
      }

      final folder = _findFolder(folders, remoteFolder);
      if (folder != null) {
        (folder['playlists'] as List<Map>).add(copy);
        return;
      }

      final newFolder = Map<String, dynamic>.from(remoteFolder);
      newFolder['playlists'] = <Map>[copy];
      folders.add(newFolder);
      foldersAdded++;
    }

    void mergeRemote(Map remote, Map? remoteFolder) {
      if (_idOf(remote) == null) return;
      final local = findMatch(remote);
      if (local != null) {
        mergeInto(local, remote);
      } else {
        addPlaylist(remote, remoteFolder);
      }
    }

    for (final playlist in remoteTopLevel) {
      mergeRemote(playlist, null);
    }
    for (final remoteFolder in remoteFolders) {
      final playlists = _mapList(remoteFolder['playlists']);
      if (playlists.isEmpty && _findFolder(folders, remoteFolder) == null) {
        // Empty folder the other device created: keep it so the structure
        // matches on both sides.
        final newFolder = Map<String, dynamic>.from(remoteFolder);
        newFolder['playlists'] = <Map>[];
        folders.add(newFolder);
        foldersAdded++;
        changed = true;
        continue;
      }
      for (final playlist in playlists) {
        mergeRemote(playlist, remoteFolder);
      }
    }

    return (
      topLevel: topLevel,
      folders: folders,
      playlistsAdded: playlistsAdded,
      songsAdded: songsAdded,
      foldersAdded: foldersAdded,
      changed: changed,
    );
  }

  static Map? _findFolder(List<Map> folders, Map wanted) {
    final id = wanted['id']?.toString();
    final name = wanted['name']?.toString().trim().toLowerCase();
    for (final folder in folders) {
      if (id != null && folder['id']?.toString() == id) return folder;
    }
    for (final folder in folders) {
      if (name != null &&
          folder['name']?.toString().trim().toLowerCase() == name) {
        return folder;
      }
    }
    return null;
  }

  static bool _sameOrder(List<Map> a, List<Map> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (_idOf(a[i]) != _idOf(b[i])) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String? _idOf(Map item) {
    final id = item['ytid']?.toString().trim();
    return id == null || id.isEmpty ? null : id;
  }

  static String? _titleKey(Map playlist) {
    final title = playlist['title']?.toString().trim().toLowerCase();
    return title == null || title.isEmpty ? null : title;
  }

  static int _intOf(dynamic value) => value is num ? value.toInt() : 0;

  static DateTime? _dateOf(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static List<Map> _mapList(dynamic value) =>
      value is List ? value.whereType<Map>().toList() : <Map>[];

  static List<String> _stringList(dynamic value) => value is List
      ? value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
      : <String>[];

  /// Hive stores DateTime natively; JSON does not. Wrap them on the way out
  /// and unwrap on the way in so `lastPlayed` survives the round trip.
  static dynamic _encodeValue(dynamic value) {
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

  static dynamic _decodeValue(dynamic value) {
    if (value is List) {
      return value.map(_decodeValue).toList();
    }
    if (value is Map) {
      if (value[_dateTimeMarker] == 'DateTime') {
        return DateTime.tryParse(value['value']?.toString() ?? '')?.toLocal() ??
            value;
      }
      return value.map(
        (key, value) => MapEntry(key.toString(), _decodeValue(value)),
      );
    }
    return value;
  }
}
