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

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/downloads_location_service.dart';
import 'package:musify/services/io_service.dart';
import 'package:musify/services/playlist_download_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/widgets/confirmation_dialog.dart';
import 'package:musify/widgets/custom_bar.dart';
import 'package:musify/widgets/section_header.dart';
import 'package:musify/widgets/shapes/four_sided_cookie_shape.dart';

/// Window and layout options, shown on Windows, Linux and macOS only.
class DesktopSettingsSection extends StatelessWidget {
  const DesktopSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;

    return Column(
      children: [
        SectionHeader(title: l10n.desktop, icon: FluentIcons.desktop_24_filled),
        const _InterfaceScaleBar(),
        _SettingSwitch(
          title: l10n.startMaximized,
          description: l10n.startMaximizedDescription,
          icon: FluentIcons.maximize_24_regular,
          setting: startMaximized,
          storageKey: 'startMaximized',
        ),
        _SettingSwitch(
          title: l10n.customTitleBar,
          description: l10n.customTitleBarDescription,
          icon: FluentIcons.color_background_24_regular,
          setting: customTitleBar,
          storageKey: 'customTitleBar',
        ),
        const _DownloadsFolderBar(),
        CustomBar(
          l10n.keyboardShortcuts,
          FluentIcons.keyboard_24_regular,
          description: l10n.keyboardShortcutsDescription,
          borderRadius: commonCustomBarRadiusLast,
          onTap: () => context.push('/settings/keyboard-shortcuts'),
        ),
      ],
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.title,
    required this.description,
    required this.icon,
    required this.setting,
    required this.storageKey,
  });

  final String title;
  final String description;
  final IconData icon;
  final ValueNotifier<bool> setting;
  final String storageKey;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: setting,
      builder: (context, value, _) => CustomBar(
        title,
        icon,
        description: description,
        onTap: () => _set(!value),
        trailing: Switch(value: value, onChanged: _set),
      ),
    );
  }

  void _set(bool value) {
    setting.value = value;
    addOrUpdateData<bool>('settings', storageKey, value);
  }
}

/// A [CustomBar] with the scale slider underneath.
class _InterfaceScaleBar extends StatefulWidget {
  const _InterfaceScaleBar();

  @override
  State<_InterfaceScaleBar> createState() => _InterfaceScaleBarState();
}

class _InterfaceScaleBarState extends State<_InterfaceScaleBar> {
  static const _step = 0.05;

  // Applied on release: rescaling while dragging moves the slider away.
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n!;

    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: commonCustomBarRadiusFirst,
      clipBehavior: Clip.antiAlias,
      child: ValueListenableBuilder<double>(
        valueListenable: interfaceScale,
        builder: (context, applied, _) {
          final scale = _dragValue ?? applied;
          final percent = '${(scale * 100).round()}%';
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Column(
              children: [
                Row(
                  children: [
                    FourSidedCookieShape(
                      size: 52,
                      color: colorScheme.secondaryContainer,
                      child: Icon(
                        FluentIcons.text_font_size_24_regular,
                        size: 26,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.interfaceScale,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.interfaceScaleDescription,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        percent,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 54),
                  child: SliderTheme(
                    data: SliderTheme.of(
                      context,
                    ).copyWith(tickMarkShape: SliderTickMarkShape.noTickMark),
                    child: Slider(
                      value: scale,
                      min: minInterfaceScale,
                      max: maxInterfaceScale,
                      divisions:
                          ((maxInterfaceScale - minInterfaceScale) / _step)
                              .round(),
                      label: percent,
                      onChanged: (value) => setState(() => _dragValue = value),
                      onChangeEnd: _save,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _save(double value) {
    setState(() => _dragValue = null);
    final rounded = (value / _step).round() * _step;
    interfaceScale.value = double.parse(rounded.toStringAsFixed(2));
    addOrUpdateData<double>('settings', 'interfaceScale', interfaceScale.value);
  }
}

class _DownloadsFolderBar extends StatefulWidget {
  const _DownloadsFolderBar();

  @override
  State<_DownloadsFolderBar> createState() => _DownloadsFolderBarState();
}

class _DownloadsFolderBarState extends State<_DownloadsFolderBar> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    final custom = DownloadsLocation.customPath;
    final description = DownloadsLocation.unavailable
        ? l10n.downloadsFolderUnavailable(custom ?? '')
        : custom ??
              '${l10n.downloadsFolderDefault} (${DownloadsLocation.defaultPath})';

    return CustomBar(
      l10n.downloadsFolder,
      FluentIcons.folder_open_24_regular,
      description: description,
      onTap: _showOptions,
    );
  }

  void _showOptions() {
    final l10n = context.l10n!;
    final colorScheme = Theme.of(context).colorScheme;
    final custom = DownloadsLocation.customPath;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          FluentIcons.folder_open_24_regular,
          color: colorScheme.primary,
          size: 32,
        ),
        title: Text(l10n.downloadsFolder),
        content: Container(
          constraints: const BoxConstraints(minWidth: 320, maxWidth: 420),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: SelectableText(
            custom ?? DownloadsLocation.defaultPath,
            textAlign: TextAlign.center,
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          if (custom != null)
            OutlinedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _confirmChange(null);
              },
              child: Text(l10n.downloadsFolderReset),
            ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _pickFolder();
            },
            child: Text(l10n.downloadsFolderChoose),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFolder() async {
    String? picked;
    try {
      picked = await FilePicker.getDirectoryPath(
        dialogTitle: context.l10n!.downloadsFolder,
        initialDirectory: downloadsDirPath,
      );
    } catch (e, stackTrace) {
      logger.log('Folder picker failed', error: e, stackTrace: stackTrace);
      if (mounted) {
        showToast(context, context.l10n!.downloadsFolderPickerUnavailable);
      }
      return;
    }
    if (picked != null && mounted) _confirmChange(picked);
  }

  /// [folder] is null for the default location.
  void _confirmChange(String? folder) {
    final l10n = context.l10n!;
    if (offlinePlaylistService.activeDownloads.isNotEmpty) {
      showToast(context, l10n.downloadsFolderBusy);
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        confirmationMessage: l10n.downloadsFolderMoveConfirm(
          folder ?? DownloadsLocation.defaultPath,
        ),
        submitMessage: l10n.confirm,
        onCancel: () => Navigator.pop(dialogContext),
        onSubmit: () {
          Navigator.pop(dialogContext);
          _move(folder);
        },
      ),
    );
  }

  Future<void> _move(String? folder) async {
    final l10n = context.l10n!;
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Expanded(child: Text(l10n.downloadsFolderMoving)),
              ],
            ),
          ),
        ),
      ),
    );

    final status = await DownloadsLocation.change(folder);
    navigator.pop();
    if (!mounted) return;
    setState(() {});
    showToast(context, switch (status) {
      DownloadsMoveStatus.moved => l10n.downloadsFolderMoved,
      DownloadsMoveStatus.partiallyMoved => l10n.downloadsFolderPartiallyMoved,
      DownloadsMoveStatus.notWritable => l10n.downloadsFolderNotWritable,
    });
  }
}
