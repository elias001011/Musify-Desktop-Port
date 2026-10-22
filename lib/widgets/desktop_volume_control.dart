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
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/utilities/platform_utils.dart';

bool get supportsDesktopVolumeControl => isDesktopPlatform;

/// Speaker button that unfolds into an inline volume slider.
///
/// Tap opens/closes the slider, right click mutes and restores, and the mouse wheel over the control adjusts the volume.
class DesktopVolumeControl extends StatefulWidget {
  const DesktopVolumeControl({
    super.key,
    this.iconSize = 22,
    this.sliderWidth = 112,
  });

  final double iconSize;
  final double sliderWidth;

  @override
  State<DesktopVolumeControl> createState() => _DesktopVolumeControlState();
}

class _DesktopVolumeControlState extends State<DesktopVolumeControl> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    if (!supportsDesktopVolumeControl) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<double>(
      stream: audioHandler.volumeStream,
      initialData: audioHandler.volume,
      builder: (context, snapshot) {
        final volume = (snapshot.data ?? 1.0).clamp(0.0, 1.0);

        return Listener(
          onPointerSignal: _onScroll,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onSecondaryTap: audioHandler.toggleMute,
                child: IconButton(
                  icon: Icon(
                    _iconForVolume(volume),
                    color: colorScheme.primary,
                  ),
                  iconSize: widget.iconSize,
                  tooltip: context.l10n!.volume,
                  style: IconButton.styleFrom(
                    backgroundColor: _isExpanded
                        ? colorScheme.primary.withValues(alpha: 0.15)
                        : Colors.transparent,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => setState(() => _isExpanded = !_isExpanded),
                ),
              ),
              ClipRect(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: _isExpanded ? widget.sliderWidth : 0,
                  child: _isExpanded
                      ? SizedBox(
                          width: widget.sliderWidth,
                          child: Slider(
                            value: volume,
                            semanticFormatterCallback: (value) =>
                                '${(value * 100).round()}%',
                            onChanged: audioHandler.setVolume,
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (delta == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      audioHandler.setVolume(
        (audioHandler.volume - delta / 400).clamp(0.0, 1.0),
      );
    });
  }

  IconData _iconForVolume(double volume) {
    if (volume <= 0.0) return FluentIcons.speaker_mute_24_regular;
    if (volume < 0.5) return FluentIcons.speaker_1_24_regular;
    return FluentIcons.speaker_2_24_regular;
  }
}
