import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/utilities/startup_support.dart';

void main() {
  late Directory root;
  late Directory legacy;
  late Directory target;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('musify_migration_test');
    legacy = Directory('${root.path}/Documents')..createSync(recursive: true);
    target = Directory('${root.path}/support')..createSync(recursive: true);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('copies Hive boxes and leaves the legacy directory intact', () async {
    File('${legacy.path}/settings.hive').writeAsStringSync('settings');
    File('${legacy.path}/user.hive').writeAsStringSync('user');
    final tracks = Directory('${legacy.path}/tracks')..createSync();
    File('${tracks.path}/dQw4w9WgXcQ.m4a').writeAsStringSync('audio');

    final report = await copyHiveBoxes(from: legacy, to: target);

    expect(report.failed, isEmpty);
    expect(report.copied, containsAll(['settings.hive', 'user.hive']));
    expect(File('${target.path}/settings.hive').readAsStringSync(), 'settings');
    expect(File('${target.path}/user.hive').readAsStringSync(), 'user');
    expect(File('${legacy.path}/settings.hive').existsSync(), isTrue);
    expect(File('${legacy.path}/user.hive').existsSync(), isTrue);
    expect(report.copied, isNot(contains('usernobackup.hive')));
    // Downloads keep playing from their stored absolute paths.
    expect(Directory('${target.path}/tracks').existsSync(), isFalse);
    expect(File('${tracks.path}/dQw4w9WgXcQ.m4a').existsSync(), isTrue);
    expect(
      target.listSync().where((e) => e.path.endsWith('.partial')),
      isEmpty,
    );
  });

  test('does nothing once the data directory holds a box', () async {
    File('${legacy.path}/settings.hive').writeAsStringSync('legacy');
    File('${legacy.path}/user.hive').writeAsStringSync('legacy user');
    File('${target.path}/settings.hive').writeAsStringSync('current');

    final report = await copyHiveBoxes(from: legacy, to: target);

    expect(report.hasWork, isFalse);
    expect(File('${target.path}/settings.hive').readAsStringSync(), 'current');
    expect(File('${target.path}/user.hive').existsSync(), isFalse);
  });

  test('is a no-op on the second start', () async {
    File('${legacy.path}/settings.hive').writeAsStringSync('settings');

    final first = await copyHiveBoxes(from: legacy, to: target);
    File('${legacy.path}/settings.hive').writeAsStringSync('changed later');
    final second = await copyHiveBoxes(from: legacy, to: target);

    expect(first.copied, ['settings.hive']);
    expect(second.hasWork, isFalse);
    expect(File('${target.path}/settings.hive').readAsStringSync(), 'settings');
  });

  test('ignores a documents directory without Hive boxes', () async {
    File('${legacy.path}/notes.txt').writeAsStringSync('mine');

    final report = await copyHiveBoxes(from: legacy, to: target);

    expect(report.hasWork, isFalse);
    expect(target.listSync(), isEmpty);
  });

  test('is a no-op when there is no legacy directory', () async {
    await legacy.delete(recursive: true);

    final report = await copyHiveBoxes(from: legacy, to: target);

    expect(report.hasWork, isFalse);
  });

  test('is a no-op when source and target are the same directory', () async {
    File('${target.path}/settings.hive').writeAsStringSync('settings');

    final report = await copyHiveBoxes(from: target, to: target);

    expect(report.hasWork, isFalse);
    expect(File('${target.path}/settings.hive').readAsStringSync(), 'settings');
  });

  test('finds boxes by the lower-case names Hive writes', () async {
    File('${legacy.path}/usernobackup.hive').writeAsStringSync('offline');

    final report = await copyHiveBoxes(from: legacy, to: target);

    expect(report.copied, ['usernobackup.hive']);
    expect(
      File('${target.path}/usernobackup.hive').readAsStringSync(),
      'offline',
    );
  });
}
