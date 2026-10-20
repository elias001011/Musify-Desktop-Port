import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

import 'package:musify/services/local_sync/sync_data.dart';

class SyncSecurity {
  static final _cipher = AesGcm.with256bits();
  static final _exchange = X25519();
  static String randomToken([int length = 32]) {
    final random = Random.secure();
    return base64UrlEncode(List.generate(length, (_) => random.nextInt(256)));
  }

  static Future<Map<String, dynamic>> seal(
    String secret,
    Map<String, dynamic> body,
    String context,
  ) async {
    final box = await _cipher.encrypt(
      utf8.encode(canonicalSync(body)),
      secretKey: SecretKey(base64Url.decode(secret)),
      aad: utf8.encode(context),
    );
    return {
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  static Future<Map<String, dynamic>> open(
    String secret,
    Map box,
    String context,
  ) async {
    final nonce = base64Decode(box['nonce'] as String);
    final mac = base64Decode(box['mac'] as String);
    if (nonce.length != 12 || mac.length != 16)
      throw const FormatException('Invalid encrypted message');
    final clear = await _cipher.decrypt(
      SecretBox(
        base64Decode(box['ciphertext'] as String),
        nonce: nonce,
        mac: Mac(mac),
      ),
      secretKey: SecretKey(base64Url.decode(secret)),
      aad: utf8.encode(context),
    );
    final value = jsonDecode(utf8.decode(clear));
    if (value is! Map) throw const FormatException('Invalid encrypted body');
    validateSyncJson(value);
    return Map<String, dynamic>.from(value);
  }

  static Future<PairingKeys> pairingKeys() async =>
      PairingKeys(await _exchange.newKeyPair(), randomToken());
}

class PairingKeys {
  PairingKeys(this.keyPair, this.nonce);
  final SimpleKeyPair keyPair;
  final String nonce;
  Future<Map<String, dynamic>> reveal() async => {
    'publicKey': base64Encode((await keyPair.extractPublicKey()).bytes),
    'nonce': nonce,
  };
  Future<String> commitment() async => syncDigest(await reveal());

  Future<({String secret, String pin})> agree(
    Map remote,
    String expectedCommitment,
    String context,
  ) async {
    if (syncDigest(remote) != expectedCommitment || remote['nonce'] is! String)
      throw const FormatException('Pairing identity changed');
    final bytes = base64Decode(remote['publicKey'] as String);
    if (bytes.length != 32) throw const FormatException('Invalid pairing key');
    final shared = await X25519().sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(bytes, type: KeyPairType.x25519),
    );
    if ((await shared.extractBytes()).every((byte) => byte == 0))
      throw const FormatException('Invalid pairing key');
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: shared,
      nonce: utf8.encode(context),
      info: utf8.encode('Musify Local Sync v2'),
    );
    final secret = await key.extractBytes();
    final digest = hash.Hmac(
      hash.sha256,
      secret,
    ).convert(utf8.encode('pairing verification')).bytes;
    final code =
        ((digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3]) %
        1000000;
    return (
      secret: base64UrlEncode(secret),
      pin: code.toString().padLeft(6, '0'),
    );
  }
}
