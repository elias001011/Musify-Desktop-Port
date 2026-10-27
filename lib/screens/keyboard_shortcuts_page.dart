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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/services/keyboard_shortcuts_manager.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/widgets/confirmation_dialog.dart';
import 'package:musify/widgets/custom_bar.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';
import 'package:musify/widgets/section_header.dart';

const _playbackActions = [
  ShortcutAction.playPause,
  ShortcutAction.previousTrack,
  ShortcutAction.nextTrack,
  ShortcutAction.seekBackward,
  ShortcutAction.seekForward,
  ShortcutAction.volumeDown,
  ShortcutAction.volumeUp,
  ShortcutAction.toggleShuffle,
  ShortcutAction.cycleRepeat,
  ShortcutAction.toggleNowPlaying,
  ShortcutAction.toggleOfflineForCurrentSong,
];

const _navigationActions = [
  ShortcutAction.focusSearch,
  ShortcutAction.goBack,
  ShortcutAction.goHome,
  ShortcutAction.goSearch,
  ShortcutAction.goLibrary,
  ShortcutAction.goSettings,
];

class KeyboardShortcutsPage extends StatelessWidget {
  const KeyboardShortcutsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.keyboardShortcuts),
        actions: [
          IconButton(
            icon: const Icon(FluentIcons.arrow_reset_24_regular),
            tooltip: l10n.resetToDefaults,
            onPressed: () => _confirmReset(context),
          ),
        ],
      ),
      body: ValueListenableBuilder<Map<ShortcutAction, SingleActivator>>(
        valueListenable: KeyboardShortcutsManager.bindings,
        builder: (context, bindings, _) => SingleChildScrollView(
          padding: commonSingleChildScrollViewPadding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                children: [
                  _buildSection(
                    context,
                    l10n.playback,
                    FluentIcons.play_circle_24_filled,
                    _playbackActions,
                    bindings,
                  ),
                  _buildSection(
                    context,
                    l10n.navigation,
                    FluentIcons.navigation_24_filled,
                    _navigationActions,
                    bindings,
                  ),
                  const SizedBox(height: 20),
                  const MiniPlayerBottomSpace(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    IconData icon,
    List<ShortcutAction> actions,
    Map<ShortcutAction, SingleActivator> bindings,
  ) {
    return Column(
      children: [
        SectionHeader(title: title, icon: icon),
        for (var i = 0; i < actions.length; i++)
          CustomBar(
            shortcutActionLabel(context.l10n!, actions[i]),
            _actionIcons[actions[i]]!,
            borderRadius: getItemBorderRadius(i, actions.length),
            trailing: KeyCaps(bindings[actions[i]]!),
            onTap: () => _captureShortcut(context, actions[i]),
          ),
      ],
    );
  }

  void _confirmReset(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        confirmationMessage: context.l10n!.keyboardShortcutsResetConfirm,
        submitMessage: context.l10n!.resetToDefaults,
        onCancel: () => Navigator.of(dialogContext).pop(),
        onSubmit: () async {
          Navigator.of(dialogContext).pop();
          await KeyboardShortcutsManager.resetToDefaults();
          if (context.mounted) {
            showToast(context, context.l10n!.settingChangedMsg);
          }
        },
      ),
    );
  }

  Future<void> _captureShortcut(
    BuildContext context,
    ShortcutAction action,
  ) async {
    final activator = await showDialog<SingleActivator>(
      context: context,
      builder: (_) => _ShortcutCaptureDialog(action: action),
    );
    if (activator == null) return;
    await KeyboardShortcutsManager.setBinding(action, activator);
    if (context.mounted) {
      showToast(context, context.l10n!.settingChangedMsg);
    }
  }
}

const _actionIcons = <ShortcutAction, IconData>{
  ShortcutAction.playPause: FluentIcons.play_24_regular,
  ShortcutAction.previousTrack: FluentIcons.previous_24_regular,
  ShortcutAction.nextTrack: FluentIcons.next_24_regular,
  ShortcutAction.seekBackward: FluentIcons.rewind_24_regular,
  ShortcutAction.seekForward: FluentIcons.fast_forward_24_regular,
  ShortcutAction.volumeDown: FluentIcons.speaker_1_24_regular,
  ShortcutAction.volumeUp: FluentIcons.speaker_2_24_regular,
  ShortcutAction.toggleShuffle: FluentIcons.arrow_shuffle_24_regular,
  ShortcutAction.cycleRepeat: FluentIcons.arrow_repeat_all_24_regular,
  ShortcutAction.toggleNowPlaying: FluentIcons.music_note_2_24_regular,
  ShortcutAction.toggleOfflineForCurrentSong:
      FluentIcons.arrow_download_24_regular,
  ShortcutAction.focusSearch: FluentIcons.search_24_regular,
  ShortcutAction.goBack: FluentIcons.arrow_left_24_regular,
  ShortcutAction.goHome: FluentIcons.home_24_regular,
  ShortcutAction.goSearch: FluentIcons.search_24_regular,
  ShortcutAction.goLibrary: FluentIcons.library_24_regular,
  ShortcutAction.goSettings: FluentIcons.settings_24_regular,
};

// Not every font has the arrow glyphs.
const _arrowIcons = <String, IconData>{
  '↑': FluentIcons.arrow_up_16_regular,
  '↓': FluentIcons.arrow_down_16_regular,
  '←': FluentIcons.arrow_left_16_regular,
  '→': FluentIcons.arrow_right_16_regular,
};

/// The keys of a shortcut drawn as keyboard keys.
class KeyCaps extends StatelessWidget {
  const KeyCaps(this.activator, {super.key, this.large = false});

  final SingleActivator activator;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final keys = KeyboardShortcutsManager.keyLabels(activator);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        for (final key in keys)
          Container(
            constraints: BoxConstraints(minWidth: large ? 44 : 32),
            padding: EdgeInsets.symmetric(
              horizontal: large ? 12 : 9,
              vertical: large ? 8 : 5,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant, width: 2),
              ),
            ),
            child: _arrowIcons.containsKey(key)
                ? Icon(
                    _arrowIcons[key],
                    size: large ? 20 : 16,
                    color: colorScheme.onSurface,
                  )
                : Text(
                    key,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: large ? 16 : 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
          ),
      ],
    );
  }
}

/// Records the next key combination the user presses.
class _ShortcutCaptureDialog extends StatefulWidget {
  const _ShortcutCaptureDialog({required this.action});

  final ShortcutAction action;

  @override
  State<_ShortcutCaptureDialog> createState() => _ShortcutCaptureDialogState();
}

class _ShortcutCaptureDialogState extends State<_ShortcutCaptureDialog> {
  final FocusNode _focusNode = FocusNode();
  SingleActivator? _captured;
  ShortcutAction? _conflict;

  static final Set<LogicalKeyboardKey> _modifierKeys = {
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  // Swallows every key so a bound combination does not also run its action.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (_modifierKeys.contains(event.logicalKey)) return KeyEventResult.handled;

    final keyboard = HardwareKeyboard.instance;
    final activator = SingleActivator(
      event.logicalKey,
      control: keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
      meta: keyboard.isMetaPressed,
    );

    setState(() {
      _captured = activator;
      _conflict = KeyboardShortcutsManager.conflictingAction(
        activator,
        ignore: widget.action,
      );
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n!;
    final captured = _captured;
    final conflict = _conflict;

    return AlertDialog(
      icon: Icon(
        _actionIcons[widget.action],
        color: theme.colorScheme.primary,
        size: 32,
      ),
      title: Text(shortcutActionLabel(l10n, widget.action)),
      content: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.pressShortcutHint, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 72),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: captured == null
                  ? Icon(
                      FluentIcons.keyboard_24_regular,
                      size: 28,
                      color: theme.colorScheme.onSurfaceVariant,
                    )
                  : KeyCaps(captured, large: true),
            ),
            if (conflict != null) ...[
              const SizedBox(height: 12),
              Text(
                l10n.shortcutConflict(shortcutActionLabel(l10n, conflict)),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: captured == null || conflict != null
              ? null
              : () => Navigator.of(context).pop(captured),
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}

String shortcutActionLabel(AppLocalizations l10n, ShortcutAction action) {
  return switch (action) {
    ShortcutAction.playPause => l10n.shortcutPlayPause,
    ShortcutAction.nextTrack => l10n.shortcutNextTrack,
    ShortcutAction.previousTrack => l10n.shortcutPreviousTrack,
    ShortcutAction.seekForward => l10n.shortcutSeekForward,
    ShortcutAction.seekBackward => l10n.shortcutSeekBackward,
    ShortcutAction.volumeUp => l10n.shortcutVolumeUp,
    ShortcutAction.volumeDown => l10n.shortcutVolumeDown,
    ShortcutAction.toggleShuffle => l10n.shortcutToggleShuffle,
    ShortcutAction.cycleRepeat => l10n.shortcutCycleRepeat,
    ShortcutAction.toggleNowPlaying => l10n.shortcutToggleNowPlaying,
    ShortcutAction.toggleOfflineForCurrentSong =>
      l10n.shortcutToggleOfflineForCurrentSong,
    ShortcutAction.focusSearch => l10n.shortcutFocusSearch,
    ShortcutAction.goBack => l10n.shortcutGoBack,
    ShortcutAction.goHome => l10n.shortcutGoHome,
    ShortcutAction.goSearch => l10n.shortcutGoSearch,
    ShortcutAction.goLibrary => l10n.shortcutGoLibrary,
    ShortcutAction.goSettings => l10n.shortcutGoSettings,
  };
}
