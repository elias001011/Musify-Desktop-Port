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

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/platform_utils.dart';

/// The native window around the Flutter view, through the `musify/window`
/// channel of the Linux and Windows runners.
class DesktopWindow {
  DesktopWindow._();

  static const _channel = MethodChannel('musify/window');

  static String? _lastTitleBarTheme;

  /// Before the first frame, so the window opens maximized instead of jumping.
  static Future<void> maximize() => _invoke('maximize');

  static Future<void> raise() => _invoke('raise');

  static void syncTitleBar(ThemeData theme) {
    final background = theme.scaffoldBackgroundColor.toARGB32();
    final foreground = theme.colorScheme.onSurface.toARGB32();
    final dark = theme.brightness == Brightness.dark;

    final key = '$dark:$background:$foreground';
    if (key == _lastTitleBarTheme) return;
    _lastTitleBarTheme = key;

    unawaited(
      _invoke('setTitleBarTheme', {
        'dark': dark,
        'background': background,
        'foreground': foreground,
      }),
    );
  }

  /// System colours, still in the system's light or dark mode.
  static void resetTitleBar({required bool dark}) {
    final key = 'system:$dark';
    if (key == _lastTitleBarTheme) return;
    _lastTitleBarTheme = key;
    unawaited(_invoke('resetTitleBarTheme', {'dark': dark}));
  }

  static Future<void> _invoke(String method, [Object? arguments]) async {
    if (!isDesktopPlatform) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // macOS and tests have no window channel.
    } on PlatformException catch (e, stackTrace) {
      logger.log(
        'Window call $method failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}

/// Keeps the title bar in the app colours while [customTitleBar] is on.
class DesktopTitleBarTheme extends StatelessWidget {
  const DesktopTitleBarTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: customTitleBar,
      builder: (context, enabled, child) {
        if (enabled) {
          DesktopWindow.syncTitleBar(Theme.of(context));
        } else {
          DesktopWindow.resetTitleBar(
            dark: MediaQuery.platformBrightnessOf(context) == Brightness.dark,
          );
        }
        return child!;
      },
      child: child,
    );
  }
}

/// Zooms the whole interface by [interfaceScale], like a browser zoom: the app
/// is laid out at a smaller or larger logical size and scaled to the window.
class DesktopInterfaceScale extends StatelessWidget {
  const DesktopInterfaceScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: interfaceScale,
      builder: (context, scale, child) {
        if (scale == 1) return child!;
        final media = MediaQuery.of(context);
        return FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: media.size / scale,
            child: MediaQuery(
              data: media.copyWith(
                size: media.size / scale,
                devicePixelRatio: media.devicePixelRatio * scale,
                padding: media.padding / scale,
                viewPadding: media.viewPadding / scale,
                viewInsets: media.viewInsets / scale,
              ),
              child: child!,
            ),
          ),
        );
      },
      child: child,
    );
  }
}
