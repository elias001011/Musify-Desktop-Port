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
import 'package:musify/services/keyboard_shortcuts_manager.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/widgets/confirmation_dialog.dart';
import 'package:musify/widgets/custom_bar.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';

class KeyboardShortcutsPage extends StatelessWidget {
  const KeyboardShortcutsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n!.keyboardShortcuts),
        actions: [
          IconButton(
            icon: const Icon(FluentIcons.arrow_clockwise_24_filled),
            tooltip: context.l10n!.resetToDefaults,
            onPressed: () => _confirmReset(context),
          ),
        ],
      ),
      body: ValueListenableBuilder<Map<ShortcutAction, SingleActivator>>(
        valueListenable: KeyboardShortcutsManager.bindings,
        builder: (context, bindings, _) {
          const actions = ShortcutAction.values;
          return ListView.builder(
            padding: commonSingleChildScrollViewPadding,
            itemCount: actions.length + 2,
            itemBuilder: (context, index) {
              if (index == actions.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: CustomBar(
                    context.l10n!.resetToDefaults,
                    FluentIcons.arrow_clockwise_24_regular,
                    borderRadius: commonCustomBarRadius,
                    iconColor: Theme.of(context).colorScheme.error,
                    onTap: () => _confirmReset(context),
                  ),
                );
              }
              if (index == actions.length + 1) {
                return const MiniPlayerBottomSpace();
              }

              final action = actions[index];
              final activator = bindings[action]!;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: CustomBar(
                  shortcutActionLabel(context, action),
                  FluentIcons.keyboard_24_regular,
                  description: KeyboardShortcutsManager.describe(activator),
                  borderRadius: getItemBorderRadius(index, actions.length),
                  onTap: () => _captureShortcut(context, action),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _confirmReset(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => ConfirmationDialog(
        confirmationMessage: context.l10n!.keyboardShortcutsResetConfirm,
        submitMessage: context.l10n!.resetToDefaults,
        onCancel: () => Navigator.of(context).pop(),
        onSubmit: () async {
          Navigator.of(context).pop();
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
      builder: (context) => _ShortcutCaptureDialog(action: action),
    );
    if (activator == null) return;
    await KeyboardShortcutsManager.setBinding(action, activator);
    if (context.mounted) {
      showToast(context, context.l10n!.settingChangedMsg);
    }
  }
}

/// A modal that records the next key combination the user presses.
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
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return;
    }
    if (_modifierKeys.contains(event.logicalKey)) return;

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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final captured = _captured;

    return AlertDialog(
      title: Text(shortcutActionLabel(context, widget.action)),
      content: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n!.pressShortcutHint,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                captured == null
                    ? '…'
                    : KeyboardShortcutsManager.describe(captured),
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (_conflict != null) ...[
              const SizedBox(height: 12),
              Text(
                context.l10n!.shortcutConflict,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n!.cancel),
        ),
        FilledButton(
          onPressed: captured == null || _conflict != null
              ? null
              : () => Navigator.of(context).pop(captured),
          child: Text(context.l10n!.confirm),
        ),
      ],
    );
  }
}

/// The localized name shown for [action] in the settings list.
String shortcutActionLabel(BuildContext context, ShortcutAction action) {
  final l10n = context.l10n!;
  switch (action) {
    case ShortcutAction.playPause:
      return l10n.shortcutPlayPause;
    case ShortcutAction.nextTrack:
      return l10n.shortcutNextTrack;
    case ShortcutAction.previousTrack:
      return l10n.shortcutPreviousTrack;
    case ShortcutAction.seekForward:
      return l10n.shortcutSeekForward;
    case ShortcutAction.seekBackward:
      return l10n.shortcutSeekBackward;
    case ShortcutAction.volumeUp:
      return l10n.shortcutVolumeUp;
    case ShortcutAction.volumeDown:
      return l10n.shortcutVolumeDown;
    case ShortcutAction.toggleShuffle:
      return l10n.shortcutToggleShuffle;
    case ShortcutAction.cycleRepeat:
      return l10n.shortcutCycleRepeat;
    case ShortcutAction.toggleNowPlaying:
      return l10n.shortcutToggleNowPlaying;
    case ShortcutAction.focusSearch:
      return l10n.shortcutFocusSearch;
    case ShortcutAction.goHome:
      return l10n.shortcutGoHome;
    case ShortcutAction.goSearch:
      return l10n.shortcutGoSearch;
    case ShortcutAction.goLibrary:
      return l10n.shortcutGoLibrary;
    case ShortcutAction.goSettings:
      return l10n.shortcutGoSettings;
  }
}
