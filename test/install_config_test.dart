import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/install_config_service.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('musify_install_config');
  });
  tearDown(() => root.delete(recursive: true));

  Future<Directory> withBoxes(String name, [String content = 'data']) async {
    final directory = await Directory('${root.path}/$name').create();
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await File('${directory.path}/$box.hive').writeAsString('$box $content');
    }
    return directory;
  }

  group('parse', () {
    test('reads absolute paths and ignores empty or relative values', () {
      final config = InstallConfig.parse(
        'dataDir=D:\\Musify Data\ndownloadsDir=relative\\folder\n',
      );
      expect(config.dataDir, r'D:\Musify Data');
      expect(config.downloadsDir, isNull);
    });

    test('accepts POSIX and UNC paths and tolerates blank lines', () {
      final config = InstallConfig.parse(
        '\ndataDir=/srv/musify\r\ndownloadsDir=\\\\nas\\music\r\n',
      );
      expect(config.dataDir, '/srv/musify');
      expect(config.downloadsDir, r'\\nas\music');
    });

    test('empty and unrelated files mean the defaults', () {
      expect(InstallConfig.parse('').dataDir, isNull);
      expect(InstallConfig.parse('other=/x').downloadsDir, isNull);
    });

    test('keeps non-ASCII folder names intact', () async {
      final file = File('${root.path}/${InstallConfig.fileName}');
      await file.writeAsString('dataDir=/home/ç/músicas\n');
      expect((await InstallConfig.load(file: file)).dataDir, '/home/ç/músicas');
    });

    test('a UTF-8 byte order mark from the installer is ignored', () {
      expect(
        InstallConfig.parse('\uFEFFdataDir=/srv/musify\n').dataDir,
        '/srv/musify',
      );
    });

    test('a missing file is not an error', () async {
      final config = await InstallConfig.load(
        file: File('${root.path}/missing.txt'),
      );
      expect(config.dataDir, isNull);
    });
  });

  group('resolveDataDir', () {
    test(
      'copies the boxes, keeps the originals and uses the new folder',
      () async {
        final old = await withBoxes('old');
        final target = '${root.path}/new/deeper';
        final used = await InstallConfig(dataDir: target)
            .resolveDataDir(old.path);
        expect(used, target);
        expect(File('$target/user.hive').readAsStringSync(), 'user data');
        expect(File('${old.path}/user.hive').existsSync(), isTrue);
        expect(
          Directory(target).listSync().any((e) => e.path.endsWith('.partial')),
          isFalse,
        );
      },
    );

    test('never overwrites boxes already in the chosen folder', () async {
      final old = await withBoxes('old', 'old');
      final chosen = await withBoxes('chosen', 'newer');
      final used = await InstallConfig(dataDir: chosen.path)
          .resolveDataDir(old.path);
      expect(used, chosen.path);
      expect(File('${chosen.path}/user.hive').readAsStringSync(), 'user newer');
    });

    test('same folder, or no choice, keeps the default', () async {
      final old = await withBoxes('old');
      expect(await const InstallConfig().resolveDataDir(old.path), old.path);
      expect(
        await InstallConfig(dataDir: '${old.path}/').resolveDataDir(old.path),
        old.path,
      );
    });

    test(
      'an unusable folder falls back to the default without touching data',
      () async {
        final old = await withBoxes('old');
        final blocker = File('${root.path}/file');
        await blocker.writeAsString('x');
        final messages = <String>[];
        final used = await InstallConfig(dataDir: '${blocker.path}/sub')
            .resolveDataDir(old.path, log: messages.add);
        expect(used, old.path);
        expect(messages, isNotEmpty);
        expect(File('${old.path}/user.hive').readAsStringSync(), 'user data');
      },
    );

    test(
      'a fresh install with nothing to copy still uses the chosen folder',
      () async {
        final empty = await Directory('${root.path}/empty').create();
        final used = await InstallConfig(dataDir: '${root.path}/chosen')
            .resolveDataDir(empty.path);
        expect(used, '${root.path}/chosen');
        expect(Directory(used).existsSync(), isTrue);
      },
    );
  });

  group('applyDownloadsDir', () {
    late Directory hive;
    setUp(() async {
      hive = await Directory('${root.path}/hive').create();
      Hive.init(hive.path);
      await Hive.openBox('userNoBackup');
    });
    tearDown(Hive.close);

    test('sets the folder once and creates it', () async {
      final target = '${root.path}/music';
      await InstallConfig(downloadsDir: target).applyDownloadsDir();
      expect(Hive.box('userNoBackup').get('downloadsDirectory'), target);
      expect(Directory(target).existsSync(), isTrue);
    });

    test('a folder chosen in the app wins over the installer', () async {
      await Hive.box('userNoBackup').put('downloadsDirectory', '/in/app');
      await InstallConfig(downloadsDir: '${root.path}/music')
          .applyDownloadsDir();
      expect(Hive.box('userNoBackup').get('downloadsDirectory'), '/in/app');
    });

    test('later in-app changes are not undone on the next start', () async {
      final config = InstallConfig(downloadsDir: '${root.path}/music');
      await config.applyDownloadsDir();
      await Hive.box('userNoBackup').put('downloadsDirectory', '/in/app');
      await config.applyDownloadsDir();
      expect(Hive.box('userNoBackup').get('downloadsDirectory'), '/in/app');
    });
  });
}
