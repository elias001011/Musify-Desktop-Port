import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/settings_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/downloads_location_service.dart';
import 'package:musify/services/io_service.dart';
import 'package:musify/services/local_sync_service.dart';
import 'package:musify/services/settings_manager.dart';

class _Handler extends MusifyAudioHandler {
  @override
  Stream<List<Map>> get queueAsMapStream => Stream.value([]);
}

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('musify_mobile_settings');
    Hive.init(directory.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box);
    }
    applicationDirPath = directory.path;
  });
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    audioHandler = _Handler();
    await Hive.box('settings').put('localSyncEnabled', true);
    reloadSettingsFromStorage();
  });
  tearDown(() async {
    await audioHandler.audioPlayer.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
  tearDownAll(() async {
    await LocalSyncService.instance.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  Future<void> page(WidgetTester tester, TargetPlatform platform) async {
    debugDefaultTargetPlatformOverride = platform;
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: SettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Android offers Local Sync without desktop settings', (
    tester,
  ) async {
    await page(tester, TargetPlatform.android);
    expect(find.text('Local sync'), findsOneWidget);
    expect(find.text('Choose what to sync'), findsOneWidget);
    expect(find.text('Desktop layout'), findsNothing);
    expect(find.text('Keyboard shortcuts'), findsNothing);
    expect(find.text('Downloads folder'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('desktop retains its platform options', (tester) async {
    await page(tester, TargetPlatform.linux);
    expect(find.text('Local sync'), findsOneWidget);
    expect(find.text('Desktop layout'), findsOneWidget);
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    debugDefaultTargetPlatformOverride = null;
  });
  test('Android ignores a desktop download-folder preference', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await Hive.box('userNoBackup')
        .put('downloadsDirectory', directory.parent.path);
    await DownloadsLocation.initialise();
    expect(downloadsDirPath, applicationDirPath);
    await expectLater(
      DownloadsLocation.change(directory.parent.path),
      throwsUnsupportedError,
    );
  });
}
