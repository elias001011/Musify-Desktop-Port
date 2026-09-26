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
import 'package:musify/constants/app_constants.dart';
import 'package:musify/main.dart';

/// Talks to the desktop runners (`linux/runner/my_application.cc` and
/// `windows/runner/flutter_window.cpp`) about the native window around the
/// Flutter view: the title bar colours and the initial window state.
class DesktopWindow {
  DesktopWindow._();

  static const _channel = MethodChannel('musify/window');

  static String? _lastTitleBarTheme;

  /// Maximizes the window. Called before the first frame, it makes the window
  /// appear maximized instead of resizing after it shows up.
  static Future<void> maximize() => _invoke('maximize');

  /// Paints the native title bar with the app's own colours, so it follows
  /// the light/dark theme and the accent instead of the system theme.
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

  static Future<void> _invoke(String method, [Object? arguments]) async {
    if (!isDesktopPlatform) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // A runner without the window channel (macOS, tests): nothing to do.
    } on PlatformException catch (e, stackTrace) {
      logger.log(
        'Window call $method failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}

/// Keeps the native title bar in step with the theme above it. Placed in
/// `MaterialApp.builder`, so it rebuilds (and repaints the title bar) whenever
/// the theme mode or accent colour changes.
class DesktopTitleBarTheme extends StatelessWidget {
  const DesktopTitleBarTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    DesktopWindow.syncTitleBar(Theme.of(context));
    return child;
  }
}
