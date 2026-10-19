import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
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
  Future<void> setVolume(double next) async {
    value = next;
    changes.add(next);
  }
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const Scaffold(
        body: Center(child: DesktopVolumeControl(iconSize: 22)),
      ),
    ),
  );

  testWidgets(
    'desktop control uses theme colors and publishes volume changes',
    (tester) async {
      await mount(tester);
      final colors = Theme.of(tester.element(find.byType(IconButton)))
          .colorScheme;
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(
        button.style!.backgroundColor!.resolve({}),
        colors.primaryContainer,
      );
      expect((button.icon as Icon).color, colors.onPrimaryContainer);
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(find.text('50%'), findsOneWidget);
      final slider = tester.widget<Slider>(find.byType(Slider));
      final theme = SliderTheme.of(tester.element(find.byType(Slider)));
      expect(theme.trackHeight, 6);
      expect(theme.activeTrackColor, colors.primary);
      expect(theme.inactiveTrackColor, colors.surfaceContainerHighest);
      slider.onChanged!(0.75);
      await tester.pumpAndSettle();
      expect(audioHandler.volume, 0.75);
      expect(find.text('75%'), findsOneWidget);
      await audioHandler.setVolume(0.25);
      await tester.pumpAndSettle();
      expect(find.text('25%'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 0.25);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'wheel adjusts current volume and clamps both ends',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      final center = tester.getCenter(find.byType(Slider));
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

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform keeps the desktop control hidden', (tester) async {
      await mount(tester);
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(Slider), findsNothing);
    }, variant: TargetPlatformVariant.only(platform));
  }
}
