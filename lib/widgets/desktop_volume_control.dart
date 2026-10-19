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
import 'package:musify/main.dart';
import 'package:musify/utilities/platform_utils.dart';

bool get supportsDesktopVolumeControl => isDesktopPlatform;

class DesktopVolumeControl extends StatefulWidget {
  const DesktopVolumeControl({
    super.key,
    required this.iconSize,
    this.sliderWidth = 136,
    this.compact = false,
  });

  final double iconSize;
  final double sliderWidth;
  final bool compact;

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

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                _iconForVolume(volume),
                color: colorScheme.onPrimaryContainer,
              ),
              iconSize: widget.iconSize,
              tooltip: 'Volume',
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => setState(() => _isExpanded = !_isExpanded),
            ),
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: _isExpanded
                    ? SizedBox(
                        width: widget.sliderWidth + 44,
                        child: Listener(
                          onPointerSignal: (event) {
                            if (event is! PointerScrollEvent) return;
                            final delta = event.scrollDelta.dy != 0
                                ? event.scrollDelta.dy
                                : event.scrollDelta.dx;
                            if (delta == 0) return;
                            GestureBinding.instance.pointerSignalResolver
                                .register(event, (_) {
                                  audioHandler.setVolume(
                                    (audioHandler.volume - delta.sign * 0.05)
                                        .clamp(0.0, 1.0),
                                  );
                                });
                          },
                          child: Row(
                            children: [
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 6,
                                    activeTrackColor: colorScheme.primary,
                                    inactiveTrackColor:
                                        colorScheme.surfaceContainerHighest,
                                    thumbColor: colorScheme.primary,
                                  ),
                                  child: Slider(
                                    value: volume,
                                    semanticFormatterCallback: (value) =>
                                        '${(value * 100).round()}%',
                                    onChanged: audioHandler.setVolume,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 44,
                                child: Text(
                                  '${(volume * 100).round()}%',
                                  textAlign: TextAlign.end,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: colorScheme.onSurface),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
    );
  }

  IconData _iconForVolume(double volume) {
    if (volume <= 0.0) return FluentIcons.speaker_mute_24_regular;
    if (volume < 0.5) return FluentIcons.speaker_1_24_regular;
    return widget.compact
        ? FluentIcons.speaker_2_20_regular
        : FluentIcons.speaker_2_24_regular;
  }
}
