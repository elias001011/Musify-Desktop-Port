import 'package:audio_service/audio_service.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/common_services.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/settings_manager.dart';

/// Builds the system prompt for one turn.
///
/// App state is injected directly rather than left for the model to fetch. The
/// assistant used to burn a whole tool round on `get_library_index` just to
/// learn what was playing, which is both slow and a chance to get it wrong.
/// Large collections are still summarised rather than dumped: playlist *names*
/// go in the prompt, and the model calls `get_library_item` when it needs the
/// songs inside one.
String buildAiSystemPrompt() {
  final sections = <String>[
    _identity(),
    _language(),
    _clock(),
    _grounding(),
    _appState(),
    _actionPolicy(),
  ];

  return sections.where((section) => section.isNotEmpty).join('\n\n');
}

String _identity() =>
    'You are ${aiName.value}, the assistant built into the Musify AI music '
    'player. You are talking to the person using the app, and you can drive '
    'the app for them through tools.';

String _language() =>
    "Always reply in the language of the user's most recent message.";

String _clock() {
  final now = DateTime.now();
  final offset = now.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final hours = offset.inHours.abs().toString().padLeft(2, '0');
  final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');

  // Spelled out because models otherwise date "this weekend" or "new releases"
  // from their training cutoff.
  return 'Current date and time: ${now.toIso8601String()} (UTC$sign$hours:$minutes). '
      'Use this as the truth for "today", "this week", "this year" and any '
      'relative date. Never infer the current date from your training data.';
}

String _grounding() =>
    'Everything you state about the user\'s library, playback, or any specific '
    'song, album or artist must come from a tool result in this conversation '
    'or from the app state below. If you do not have it, call a tool or say '
    'you do not know. Never invent a song id, a link, a play count or a '
    'release date.';

String _appState() {
  final lines = <String>[];

  final current = audioHandler.currentSong;
  if (current != null) {
    final title = current['title'] ?? 'unknown';
    final artist = current['artist'] ?? 'unknown artist';
    final ytid = current['ytid'];
    lines.add(
      '- Now playing: "$title" by $artist${ytid != null ? ' (ytid $ytid)' : ''}.',
    );
  } else {
    lines.add('- Nothing is playing right now.');
  }

  final queue = audioHandler.currentQueueList;
  if (queue.isNotEmpty) {
    lines.add(
      '- Queue: ${queue.length} songs, currently at position '
      '${audioHandler.currentQueueIndex + 1}.',
    );
  }

  final modes = <String>[
    if (shuffleNotifier.value) 'shuffle on',
    if (repeatNotifier.value == AudioServiceRepeatMode.all) 'repeat all',
    if (repeatNotifier.value == AudioServiceRepeatMode.one) 'repeat one',
    if (sleepTimerNotifier.value != null)
      'sleep timer ${sleepTimerNotifier.value!.inMinutes} min',
  ];
  if (modes.isNotEmpty) lines.add('- Playback modes: ${modes.join(', ')}.');

  final playlistNames = userCustomPlaylists.value
      .map((playlist) => playlist['title']?.toString())
      .whereType<String>()
      .take(25)
      .toList();
  if (playlistNames.isNotEmpty) {
    lines.add(
      '- The user\'s own playlists (call get_library_item with one of these to '
      'see its songs): ${playlistNames.join('; ')}.',
    );
  }

  lines.add(
    '- Library counts: ${userLikedSongsList.value.length} liked songs, '
    '${userOfflineSongs.value.length} offline songs.',
  );

  if (userLikedRadioStations.value.isNotEmpty) {
    lines.add(
      '- Liked radio stations: ${userLikedRadioStations.value.length}.',
    );
  }

  if (aiIncludeRecentlyPlayed.value && userRecentlyPlayed.value.isNotEmpty) {
    final recent = userRecentlyPlayed.value
        .take(10)
        .map((song) => '${song['title']} - ${song['artist'] ?? 'unknown'}')
        .join('; ');
    lines.add('- Recently played, newest first: $recent.');
  }

  if (offlineMode.value) {
    lines.add(
      '- The app is in offline mode: searching and streaming are unavailable, '
      'so only work with offline songs.',
    );
  }

  return 'Current app state:\n${lines.join('\n')}';
}

String _actionPolicy() => '''
How to act:
- Never guess a song, playlist or artist id. Search first, then act on the exact result you got back.
- One specific song means play_song (or queue it). Do not wrap a single song in a playlist. Only create a playlist when there are several songs or the user asked for a playlist.
- For a mood, an activity or a vibe ("something for the gym", "music for friday"), search a few times yourself with different queries and then create the playlist. The app's search is your tool, not a task for the user.
- Unless the user clearly asked to save it, create playlists with temporary=true. They get a save button in the chat.
- When creating or renaming a playlist, pass an image url you already saw in a search result so it does not end up without a cover.
- To play a whole playlist, album or list of songs, use play_collection once instead of queueing song by song.
- The user can attach an item with the "+" button. A message starting with "[Attached <type>: {...}]" already contains the exact item they mean - use its ytid directly instead of searching again. "this" in that message refers to the attachment.
- Keep replies short and warm. The UI already shows a card for whatever you did, so do not read the data back out in a list.
- Never mention tools, rounds, providers, models or ids in your reply. Talk about music.''';
