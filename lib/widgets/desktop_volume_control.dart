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
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:musify/main.dart';

bool get supportsDesktopVolumeControl =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows);

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
                color: colorScheme.primary,
              ),
              iconSize: widget.iconSize,
              tooltip: 'Volume',
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
                          onChanged: audioHandler.setVolume,
                        ),
                      )
                    : null,
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
