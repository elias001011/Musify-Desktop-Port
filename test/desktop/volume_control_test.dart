import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/localization/app_localizations_en.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_service.dart';
import 'package:musify/widgets/desktop_volume_control.dart';

class _Handler extends MusifyAudioHandler {
  final changes = StreamController<double>.broadcast();
  double value = 0.5;
  @override
  double get volume => value;
  @override
  Stream<double> get volumeStream => changes.stream;
  @override
  Stream<List<Map>> get queueAsMapStream => Stream.value([
    {'ytid': 'test'},
  ]);
  @override
  Future<void> setVolume(double next) async {
    value = next;
    changes.add(next);
  }
}

class _VolumeLocalizations extends AppLocalizationsEn {
  @override
  String get volume => 'Localized volume';
}

class _VolumeDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _VolumeDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';
  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(_VolumeLocalizations());
  @override
  bool shouldReload(_VolumeDelegate old) => false;
}

void main() {
  late Directory directory;
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('musify_volume_test');
    Hive.init(directory.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    audioHandler = _Handler();
    await audioHandler.setVolume(0.5);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    debugDefaultTargetPlatformOverride = null;
  });
  tearDown(() async {
    unawaited((audioHandler as _Handler).changes.close());
    await audioHandler.audioPlayer.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    debugDefaultTargetPlatformOverride = null;
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: [
        const _VolumeDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const Scaffold(body: Center(child: DesktopVolumeControl())),
    ),
  );

  testWidgets(
    'speaker unfolds the slider, which publishes volume changes',
    (tester) async {
      await mount(tester);
      final colors = Theme.of(tester.element(find.byType(IconButton)))
          .colorScheme;
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect((button.icon as Icon).color, colors.primary);
      expect(
        button.tooltip,
        AppLocalizations.of(tester.element(find.byType(IconButton)))!.volume,
      );
      expect(find.byType(Slider), findsNothing);

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsOneWidget);
      tester.widget<Slider>(find.byType(Slider)).onChanged!(0.75);
      await tester.pumpAndSettle();
      expect(audioHandler.volume, 0.75);

      await audioHandler.setVolume(0.25);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 0.25);

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNothing);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'wheel adjusts volume and clamps both ends',
    (tester) async {
      await mount(tester);
      final center = tester.getCenter(find.byType(IconButton));
      Future<void> scroll(double delta) async {
        await tester.sendEventToBinding(
          PointerScrollEvent(position: center, scrollDelta: Offset(0, delta)),
        );
        await tester.pumpAndSettle();
      }

      await scroll(-20);
      expect(audioHandler.volume, closeTo(0.55, 0.0001));
      await scroll(20);
      expect(audioHandler.volume, closeTo(0.5, 0.0001));
      await audioHandler.setVolume(1);
      await scroll(-20);
      expect(audioHandler.volume, 1);
      await audioHandler.setVolume(0);
      await scroll(20);
      expect(audioHandler.volume, 0);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'right click mutes and restores the previous volume',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byType(IconButton), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(audioHandler.volume, 0);
      await tester.tap(find.byType(IconButton), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(audioHandler.volume, 0.5);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform keeps the desktop control hidden', (tester) async {
      await mount(tester);
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(Slider), findsNothing);
    }, variant: TargetPlatformVariant.only(platform));
  }
}
