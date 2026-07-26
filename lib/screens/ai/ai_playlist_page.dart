import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:musify/screens/ai/ai_chat_page.dart';
import 'package:musify/screens/playlist_page.dart';
import 'package:musify/services/ai/ai_chat_store.dart';
import 'package:musify/widgets/playlist_page/empty_playlist_state.dart';

/// Opens a playlist the assistant built in the app's normal playlist screen.
///
/// This is a resolver, not a screen: it reads the action card off the stored
/// chat message and hands it to [PlaylistPage] as in-memory data. Going through
/// the real playlist UI means the assistant's playlists get the app's sorting,
/// search, play/shuffle buttons and song menus for free, instead of a
/// second-class list living inside the chat.
class AiPlaylistPage extends StatelessWidget {
  const AiPlaylistPage({
    required this.chatId,
    required this.messageId,
    super.key,
  });

  final String chatId;
  final String messageId;

  @override
  Widget build(BuildContext context) {
    final message = AiChatStore.instance.getMessage(chatId, messageId);
    final card = message?['actionCard'] as Map?;

    if (card == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyPlaylistState(
          icon: FluentIcons.sparkle_24_regular,
          message: 'Essa playlist não está mais disponível.',
        ),
      );
    }

    final songs = (card['songs'] as List? ?? const [])
        .map((song) => _hydrate(Map<String, dynamic>.from(song as Map)))
        .toList();

    // A temp playlist that was later saved carries the real library id, and
    // only then should the page offer editing: pointing "remove song" at a
    // playlist that was never written would silently do nothing.
    final savedId = (message?['saved'] as Map?)?['playlistId']?.toString();

    return PlaylistPage(
      cubeIcon: FluentIcons.sparkle_24_filled,
      playlistData: {
        if (savedId != null) 'ytid': savedId,
        'title': (card['title'] ?? card['name'] ?? 'Playlist').toString(),
        'image': card['image'],
        'list': songs,
        if (savedId != null) 'source': 'user-created',
      },
    );
  }

  /// Rebuilds the song map shape the rest of the app expects from the compact
  /// form stored on the card.
  Map<String, dynamic> _hydrate(Map<String, dynamic> song) => {
    'id': 0,
    'ytid': song['ytid'],
    'title': song['title'],
    'artist': song['artist'] ?? '',
    'image': song['image'],
    'lowResImage': song['image'],
    'highResImage': song['image'],
    'duration': song['duration'],
  };
}

/// Route helper so callers do not have to know the path shape.
String aiPlaylistRoute(String chatId, String messageId) =>
    '${AiChatPage.routePath}/$chatId/playlist/$messageId';
