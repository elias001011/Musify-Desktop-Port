import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/no_artwork_cube.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader =
        FontLoader('packages/fluentui_system_icons/FluentSystemIcons-Regular')
          ..addFont(
            rootBundle.load(
              'packages/fluentui_system_icons/fonts/FluentSystemIcons-Regular.ttf',
            ),
          );
    await loader.load();
  });

  testWidgets(
    'the painted note fits and stays centered at desktop and compact sizes',
    (tester) async {
      for (final sample in [(274.0, 160.0), (52.0, 24.0), (320.0, 50.0)]) {
        for (final scale in [1.0, 2.0]) {
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                colorScheme: const ColorScheme.dark(
                  primaryContainer: Color(0xff204080),
                  onPrimaryContainer: Colors.white,
                  surfaceContainerHighest: Color(0xff303030),
                ),
              ),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Center(
                  child: RepaintBoundary(
                    key: key,
                    child: NullArtworkWidget(
                      size: sample.$1,
                      iconSize: sample.$2,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = (await tester.runAsync(boundary.toImage))!;
          final bytes = (await tester.runAsync(image.toByteData))!;
          var left = image.width;
          var top = image.height;
          var right = 0;
          var bottom = 0;
          for (var y = 0; y < image.height; y++) {
            for (var x = 0; x < image.width; x++) {
              final offset = (y * image.width + x) * 4;
              if (bytes.getUint8(offset) > 230 &&
                  bytes.getUint8(offset + 1) > 230 &&
                  bytes.getUint8(offset + 2) > 230) {
                if (x < left) left = x;
                if (x > right) right = x;
                if (y < top) top = y;
                if (y > bottom) bottom = y;
              }
            }
          }
          final ink = Rect.fromLTRB(
            left.toDouble(),
            top.toDouble(),
            right + 1.0,
            bottom + 1.0,
          );
          final center = Offset(sample.$1 / 2, sample.$1 / 2);
          final badge = Rect.fromCenter(
            center: center,
            width: sample.$1 * 0.4,
            height: sample.$1 * 0.4,
          );
          if (Platform.environment['MUSIFY_ARTWORK_PREVIEW']
              case final folder?) {
            final png = await tester.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.png),
            );
            await tester.runAsync(
              () =>
                  File('$folder/artwork-${sample.$1}-$scale.png')
                      .writeAsBytes(png!.buffer.asUint8List()),
            );
          }
          image.dispose();
          expect(ink.isEmpty, false);
          expect(
            badge.inflate(1).contains(ink.topLeft) &&
                badge.inflate(1).contains(ink.bottomRight),
            true,
            reason:
                'painted note $ink must fit inside badge $badge at $sample, scale $scale',
          );
          expect(
            (ink.center - center).distance,
            lessThan(2.0),
            reason: '$sample, scale $scale',
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
    variant: const TargetPlatformVariant({TargetPlatform.linux}),
  );
  testWidgets(
    'mobile keeps the requested note size',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(child: NullArtworkWidget(size: 274, iconSize: 160)),
        ),
      );
      expect(tester.widget<Icon>(find.byType(Icon)).size, 160);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}
