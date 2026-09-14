import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/library_merge_service.dart';
import 'package:musify/services/local_sync_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('musify_sync_test');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.openBox('user');
    await Hive.openBox('userNoBackup');
    await Hive.openBox('cache');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('pairing with a PIN and a two-way merge over loopback', () async {
    // Both ends share this process's storage, so the merge itself is a
    // no-op; what this covers is the HTTP handshake end to end.
    final server = LocalSyncService.forTesting();
    final client = LocalSyncService.forTesting();
    await server.startServer();
    await client.startServer();
    addTearDown(() async {
      await client.dispose();
      await server.dispose();
    });

    await Hive.box('user').put('likedSongs', [
      {'ytid': 'a', 'title': 'Song a', 'artist': 'Artist'},
    ]);

    final target = DiscoveredSyncDevice(
      ip: '127.0.0.1',
      port: server.serverPort!,
      name: 'Server',
      deviceId: 'server-device',
    );

    // The server shows a PIN; the client types it.
    final pinShown = Completer<String>();
    server.incomingPairingRequest.addListener(() {
      final request = server.incomingPairingRequest.value;
      if (request != null && !pinShown.isCompleted) {
        pinShown.complete(request.pin);
      }
    });

    final syncDone = client.syncWith(target);
    final pin = await pinShown.future.timeout(const Duration(seconds: 5));
    expect(pin, hasLength(4));
    await waitForStatus(client, LocalSyncStatus.waitingForPin);

    client.submitPin(pin);
    await syncDone.timeout(const Duration(seconds: 10));

    expect(
      client.state.value.status,
      LocalSyncStatus.success,
      reason: client.state.value.rawError,
    );
    expect(server.incomingPairingRequest.value, isNull);
    expect(client.pairedDevices.value, isNotEmpty);
    expect(LibraryMergeService.totalAdded(client.state.value.stats!), 0);
  });

  test('a wrong PIN is rejected and reported', () async {
    final server = LocalSyncService.forTesting();
    final client = LocalSyncService.forTesting();
    await server.startServer();
    await client.startServer();
    addTearDown(() async {
      await client.dispose();
      await server.dispose();
    });
    await client.forgetAllDevices();

    final target = DiscoveredSyncDevice(
      ip: '127.0.0.1',
      port: server.serverPort!,
      name: 'Server',
      deviceId: 'server-device-2',
    );

    final pinShown = Completer<void>();
    server.incomingPairingRequest.addListener(() {
      if (server.incomingPairingRequest.value != null &&
          !pinShown.isCompleted) {
        pinShown.complete();
      }
    });

    final syncDone = client.syncWith(target);
    await pinShown.future.timeout(const Duration(seconds: 5));
    await waitForStatus(client, LocalSyncStatus.waitingForPin);
    client.submitPin('0000');
    await syncDone.timeout(const Duration(seconds: 10));

    expect(client.state.value.status, LocalSyncStatus.error);
    expect(client.state.value.errorMessage, contains('Incorrect PIN'));
  });

  test('an unpaired device cannot push a library', () async {
    final server = LocalSyncService.forTesting();
    await server.startServer();
    addTearDown(server.dispose);
    await server.forgetAllDevices();

    final socket = await Socket.connect('127.0.0.1', server.serverPort!);
    final body = '{"clientId":"stranger","library":{}}';
    socket.write(
      'POST /api/sync/merge HTTP/1.1\r\n'
      'Host: 127.0.0.1\r\n'
      'Content-Type: application/json\r\n'
      'Content-Length: ${body.length}\r\n'
      'Connection: close\r\n\r\n$body',
    );
    final response = await utf8Response(socket);
    expect(response, startsWith('HTTP/1.1 403'));
  });
}

Future<void> waitForStatus(LocalSyncService service, LocalSyncStatus status) {
  if (service.state.value.status == status) return Future.value();
  final done = Completer<void>();
  void listener() {
    if (service.state.value.status == status && !done.isCompleted) {
      service.state.removeListener(listener);
      done.complete();
    }
  }

  service.state.addListener(listener);
  return done.future.timeout(const Duration(seconds: 5));
}

Future<String> utf8Response(Socket socket) async {
  final buffer = StringBuffer();
  await for (final chunk in socket) {
    buffer.write(String.fromCharCodes(chunk));
  }
  return buffer.toString();
}
