import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/local_sync/sync_security.dart';

void main() {
  test(
    'committed X25519 exchange derives the same key and six-digit code',
    () async {
      final a = await SyncSecurity.pairingKeys(),
          b = await SyncSecurity.pairingKeys();
      final commitmentA = await a.commitment(),
          commitmentB = await b.commitment();
      final left = await a.agree(
        await b.reveal(),
        commitmentB,
        'deviceA|deviceB|session',
      );
      final right = await b.agree(
        await a.reveal(),
        commitmentA,
        'deviceA|deviceB|session',
      );
      expect(left.secret, right.secret);
      expect(left.pin, right.pin);
      expect(left.pin, matches(RegExp(r'^\d{6}$')));
    },
  );
  test('changing an announced pairing identity is rejected', () async {
    final a = await SyncSecurity.pairingKeys(),
        b = await SyncSecurity.pairingKeys(),
        attacker = await SyncSecurity.pairingKeys();
    await expectLater(
      a.agree(await attacker.reveal(), await b.commitment(), 'session'),
      throwsFormatException,
    );
  });
  test('encrypted library round-trips and cannot be read with another key or route', () async {
    final key = SyncSecurity.randomToken();
    final box = await SyncSecurity.seal(key, {
      'song': 'private',
      'requestId': 'nonce',
    }, 'merge|A|B');
    expect(box.toString(), isNot(contains('private')));
    expect((await SyncSecurity.open(key, box, 'merge|A|B'))['song'], 'private');
    await expectLater(
      SyncSecurity.open(SyncSecurity.randomToken(), box, 'merge|A|B'),
      throwsA(anything),
    );
    await expectLater(
      SyncSecurity.open(key, box, 'confirm|A|B'),
      throwsA(anything),
    );
    await expectLater(
      SyncSecurity.open(key, {
        ...box,
        'mac': 'AAAAAAAAAAAAAAAAAAAAAA==',
      }, 'merge|A|B'),
      throwsA(anything),
    );
  });
}
