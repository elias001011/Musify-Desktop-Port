import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/keyboard_shortcuts_manager.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('musify_shortcuts');
    Hive.init(dir.path);
    await Hive.openBox('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  tearDown(KeyboardShortcutsManager.resetToDefaults);

  test('labels modifiers before the key', () {
    const activator = SingleActivator(
      LogicalKeyboardKey.arrowRight,
      control: true,
      shift: true,
    );
    expect(KeyboardShortcutsManager.keyLabels(activator), [
      'Ctrl',
      'Shift',
      '→',
    ]);
    expect(KeyboardShortcutsManager.describe(activator), 'Ctrl + Shift + →');
  });

  test('a new binding is stored and survives a reload', () async {
    const activator = SingleActivator(LogicalKeyboardKey.keyK, control: true);
    await KeyboardShortcutsManager.setBinding(
      ShortcutAction.playPause,
      activator,
    );

    KeyboardShortcutsManager.reload();

    final reloaded =
        KeyboardShortcutsManager.bindings.value[ShortcutAction.playPause]!;
    expect(reloaded.trigger, LogicalKeyboardKey.keyK);
    expect(reloaded.control, isTrue);
  });

  test('finds the action already using a combination', () {
    final nextTrack =
        KeyboardShortcutsManager.defaults[ShortcutAction.nextTrack]!;

    expect(
      KeyboardShortcutsManager.conflictingAction(nextTrack),
      ShortcutAction.nextTrack,
    );
    expect(
      KeyboardShortcutsManager.conflictingAction(
        nextTrack,
        ignore: ShortcutAction.nextTrack,
      ),
      isNull,
    );
  });

  test('reset restores every default', () async {
    await KeyboardShortcutsManager.setBinding(
      ShortcutAction.goHome,
      const SingleActivator(LogicalKeyboardKey.keyH, alt: true),
    );
    await KeyboardShortcutsManager.resetToDefaults();

    expect(
      KeyboardShortcutsManager.bindings.value[ShortcutAction.goHome]!.trigger,
      LogicalKeyboardKey.digit1,
    );
    expect(Hive.box('settings').get('keyboardShortcuts'), isNull);
  });
}
