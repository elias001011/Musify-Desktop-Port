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

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

PersistentBottomSheetController? _currentBottomSheetController;

PersistentBottomSheetController? showCustomBottomSheet(
  BuildContext context,
  Widget content,
) {
  final size = MediaQuery.sizeOf(context);
  final colorScheme = Theme.of(context).colorScheme;

  final controller = showBottomSheet(
    enableDrag: true,
    context: context,
    builder: (context) => _EscapeToClose(
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: size.width * 0.92,
                maxHeight: size.height * 0.65,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16),
                child: content,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  _currentBottomSheetController = controller;
  controller.closed.whenComplete(() {
    if (_currentBottomSheetController == controller) {
      _currentBottomSheetController = null;
    }
  });

  return controller;
}

void closeCurrentBottomSheet() {
  try {
    _currentBottomSheetController?.close();
  } catch (_) {}
  _currentBottomSheetController = null;
}

/// Lets Escape close a persistent bottom sheet (unlike `showModalBottomSheet`,
/// it is not a Navigator route, so Flutter's built-in Escape-to-dismiss never
/// reaches it).
///
/// `autofocus` alone was not reliable here: it is resolved at the end of the
/// frame the sheet is inserted in, racing whatever the tap that opened the
/// sheet did to focus (e.g. the row's own `InkWell`) in that same frame — a
/// bare "widget vs widget" race that sometimes lost, matching the reports of
/// Escape working, then not, until the tab was left and revisited (which
/// rebuilds the sheet fresh into a race that happened to go the other way).
/// A post-frame [FocusNode.requestFocus] runs strictly after that frame
/// settles, so it always wins.
class _EscapeToClose extends StatefulWidget {
  const _EscapeToClose({required this.child});

  final Widget child;

  @override
  State<_EscapeToClose> createState() => _EscapeToCloseState();
}

class _EscapeToCloseState extends State<_EscapeToClose> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          closeCurrentBottomSheet();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: widget.child,
    );
  }
}
