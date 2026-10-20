import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:musify/services/listening_stats_service.dart';
import 'package:musify/services/local_sync/sync_data.dart';
import 'package:musify/services/local_sync/sync_security.dart';
import 'package:musify/services/local_sync_service.dart';

import 'local_sync/fixtures.dart';

void main() {
  late Directory directory;
  late LocalSyncService server;
  late String ownId;
  late String secret;
  const peerId = 'trusted-fixture';
  var sequence = 0;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'musify_secure_transport',
    );
    Hive.init(directory.path);
    for (final name in ['user', 'userNoBackup', 'settings', 'cache']) {
      await Hive.openBox(name);
    }
  });
  setUp(() async {
    listeningStatsService.reload();
    for (final name in ['user', 'userNoBackup', 'settings', 'cache']) {
      await Hive.box(name).clear();
    }
    server = LocalSyncService.forTesting();
    await server.startServer();
    final info = jsonDecode(
      (await http.get(
        Uri.parse('http://127.0.0.1:${server.serverPort}/api/sync/info'),
      )).body,
    );
    ownId = info['deviceId'];
    secret = SyncSecurity.randomToken();
    sequence = 0;
    await server.savePairedDevice(
      PairedSyncDevice(
        deviceId: peerId,
        name: 'Fixture',
        ip: '127.0.0.1',
        port: 1,
        secret: secret,
      ),
    );
  });
  tearDown(() async {
    await server.dispose();
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<http.Response> post(String path, Map<String, dynamic> body) =>
      http.post(
        Uri.parse('http://127.0.0.1:${server.serverPort}/api/sync/$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
  Future<Map<String, dynamic>> envelope(
    String path,
    Map<String, dynamic> body,
  ) async => {
    'apiVersion': 2,
    'clientId': peerId,
    'encrypted': await SyncSecurity.seal(secret, {
      ...body,
      'requestId': SyncSecurity.randomToken(24),
      'sequence': ++sequence,
    }, 'api/sync/$path|$peerId|$ownId'),
  };
  Future<({int status, Map<String, dynamic> body})> secure(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await post(path, await envelope(path, body));
    final raw = jsonDecode(response.body) as Map;
    final clear = raw['encrypted'] is Map
        ? await SyncSecurity.open(
            secret,
            raw['encrypted'],
            'api/sync/$path|$ownId|$peerId',
          )
        : Map<String, dynamic>.from(raw);
    return (status: response.statusCode, body: clear);
  }

  Future<({String session, String shared, Map<String, dynamic> proof})>
  pair() async {
    final keys = await SyncSecurity.pairingKeys();
    final response = jsonDecode(
      (await post('pair-request', {
        'apiVersion': 2,
        'clientId': peerId,
        'clientName': 'New fixture',
        'clientPort': 1,
        'commitment': await keys.commitment(),
      })).body,
    );
    final session = response['session'] as String;
    final exchange = jsonDecode(
      (await post('pair-exchange', {
        'session': session,
        'reveal': await keys.reveal(),
      })).body,
    );
    final agreement = await keys.agree(
      exchange['reveal'],
      response['commitment'],
      '$peerId|$ownId|$session',
    );
    expect(agreement.pin, server.incomingPairingRequest.value!.pin);
    final proof = await SyncSecurity.seal(agreement.secret, {
      'pin': agreement.pin,
      'clientId': peerId,
    }, 'pair:$session');
    return (session: session, shared: agreement.secret, proof: proof);
  }

  test(
    'declaring a trusted id without its key cannot read or mutate data',
    () async {
      await Hive.box('user').put('likedSongs', [song('private')]);
      final response = await post('merge', {
        'clientId': peerId,
        'library': {
          'likedSongs': [song('injected')],
        },
      });
      expect(response.statusCode, 403);
      expect(response.body, isNot(contains('private')));
      expect(
        (Hive.box('user').get('likedSongs') as List).single['ytid'],
        'private',
      );
      final forged = await post('capabilities', {
        'apiVersion': 2,
        'clientId': peerId,
        'encrypted': await SyncSecurity.seal(SyncSecurity.randomToken(), {
          'requestId': 'wrong',
        }, 'api/sync/capabilities|$peerId|$ownId'),
      });
      expect(forged.statusCode, 403);
    },
  );

  test(
    'authenticated capabilities are encrypted and replays rejected',
    () async {
      final request = await envelope('capabilities', {});
      final first = await post('capabilities', request);
      expect(first.statusCode, 200);
      expect(first.body, isNot(contains('categories')));
      expect((await post('capabilities', request)).statusCode, 403);
    },
  );

  test('a valid key does not bypass schema validation or selection', () async {
    await Hive.box('user').put('likedSongs', [song('keep')]);
    final invalid = await secure('merge', {
      'categories': ['favourites'],
      'library': {'schemaVersion': 999},
    });
    expect(invalid.status, 400);
    await server.setCategories({SyncCategory.recap});
    final excluded = await secure('merge', {
      'categories': ['favourites'],
      'library': payload(
        document({
          'likedSongs': [song('remote')],
        }),
        categories: {SyncCategory.favourites},
      ),
    });
    expect(excluded.status, 409);
    expect((Hive.box('user').get('likedSongs') as List).single['ytid'], 'keep');
  });

  test('receiver records success only after an authenticated receipt acknowledgement', () async {
    final result = await secure('merge', {
      'categories': ['favourites'],
      'library': payload(
        document({
          'likedSongs': [song('new')],
        }),
        categories: {SyncCategory.favourites},
      ),
    });
    expect(result.status, 200);
    expect(Hive.box('settings').get('localSyncLastSyncedAt'), null);
    expect(
      (await secure('confirm', {
        'receipt': result.body['receipt'],
        'digest': 'wrong',
      })).status,
      409,
    );
    expect(Hive.box('settings').get('localSyncLastSyncedAt'), null);
    final confirmation = await secure('confirm', {
      'receipt': result.body['receipt'],
      'digest': syncDigest(result.body['library']),
    });
    expect(confirmation.status, 200);
    expect(confirmation.body['confirmed'], true);
    expect(Hive.box('settings').get('localSyncLastSyncedAt'), isNotNull);
  });

  test(
    're-pairing keeps the previous trust until both devices approve',
    () async {
      final attempt = await pair();
      expect(server.pairedDevices.value.single.secret, secret);
      final waiting = post('pair-verify', {
        'session': attempt.session,
        'proof': attempt.proof,
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(server.pairedDevices.value.single.secret, secret);
      server.approveIncomingPairing();
      final response = await waiting.timeout(const Duration(seconds: 3));
      expect(response.statusCode, 200);
      expect(server.pairedDevices.value.single.secret, attempt.shared);
    },
  );

  test(
    'rejecting a request preserves existing trust and completes the dialog',
    () async {
      final attempt = await pair();
      final completed = server.incomingPairingRequest.value!.completed;
      server.rejectIncomingPairing();
      expect(await completed, false);
      expect(
        (await post('pair-verify', {
          'session': attempt.session,
          'proof': attempt.proof,
        })).statusCode,
        403,
      );
      expect(server.pairedDevices.value.single.secret, secret);
    },
  );

  test('turning sync off cancels a pending pairing', () async {
    await pair();
    final completed = server.incomingPairingRequest.value!.completed;
    await server.stopServer();
    expect(await completed, false);
    expect(server.serverRunning.value, false);
    expect(server.pairedDevices.value.single.secret, secret);
  });
}
