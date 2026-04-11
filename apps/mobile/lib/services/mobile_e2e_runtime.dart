import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:sodium/sodium_sumo.dart';

const _e2eEnvelopeContext = 'nomade-e2e-v1';
const _scanExchangeContext = 'nomade-scan-exchange-v1';

class E2ERuntimeException implements Exception {
  const E2ERuntimeException(this.code);

  final String code;

  @override
  String toString() => code;
}

class MobileDeviceIdentity {
  const MobileDeviceIdentity({
    required this.deviceId,
    required this.encPublicKey,
    required this.encPrivateKey,
    required this.signPublicKey,
    required this.signPrivateKey,
    required this.createdAt,
  });

  final String deviceId;
  final String encPublicKey;
  final String encPrivateKey;
  final String signPublicKey;
  final String signPrivateKey;
  final String createdAt;

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'encPublicKey': encPublicKey,
      'encPrivateKey': encPrivateKey,
      'signPublicKey': signPublicKey,
      'signPrivateKey': signPrivateKey,
      'createdAt': createdAt,
    };
  }

  static MobileDeviceIdentity fromJson(Map<String, dynamic> json) {
    return MobileDeviceIdentity(
      deviceId: json['deviceId']?.toString() ?? '',
      encPublicKey: json['encPublicKey']?.toString() ?? '',
      encPrivateKey: json['encPrivateKey']?.toString() ?? '',
      signPublicKey: json['signPublicKey']?.toString() ?? '',
      signPrivateKey: json['signPrivateKey']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}

class MobilePeerDevice {
  const MobilePeerDevice({
    required this.deviceId,
    required this.encPublicKey,
    required this.signPublicKey,
    required this.addedAt,
  });

  final String deviceId;
  final String encPublicKey;
  final String signPublicKey;
  final String addedAt;

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'encPublicKey': encPublicKey,
      'signPublicKey': signPublicKey,
      'addedAt': addedAt,
    };
  }

  static MobilePeerDevice fromJson(Map<String, dynamic> json) {
    return MobilePeerDevice(
      deviceId: json['deviceId']?.toString() ?? '',
      encPublicKey: json['encPublicKey']?.toString() ?? '',
      signPublicKey: json['signPublicKey']?.toString() ?? '',
      addedAt: json['addedAt']?.toString() ?? '',
    );
  }
}

class MobileE2ESnapshot {
  const MobileE2ESnapshot({
    required this.epoch,
    required this.rootKey,
    required this.device,
    required this.peers,
    required this.seqByScope,
  });

  final int epoch;
  final String rootKey;
  final MobileDeviceIdentity device;
  final Map<String, MobilePeerDevice> peers;
  final Map<String, int> seqByScope;

  Map<String, dynamic> toJson() {
    return {
      'epoch': epoch,
      'rootKey': rootKey,
      'device': device.toJson(),
      'peers': peers.map((key, value) => MapEntry(key, value.toJson())),
      'seqByScope': seqByScope,
    };
  }

  static MobileE2ESnapshot? fromJson(Map<String, dynamic> json) {
    final rootKey = json['rootKey']?.toString() ?? '';
    final deviceRaw = json['device'];
    if (rootKey.isEmpty || deviceRaw is! Map) {
      return null;
    }

    final peersRaw = json['peers'];
    final peerMap = <String, MobilePeerDevice>{};
    if (peersRaw is Map) {
      for (final entry in peersRaw.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is Map) {
          final peer = MobilePeerDevice.fromJson(value.cast<String, dynamic>());
          if (peer.deviceId.isNotEmpty && peer.signPublicKey.isNotEmpty) {
            peerMap[key] = peer;
          }
        }
      }
    }

    final seqRaw = json['seqByScope'];
    final seqByScope = <String, int>{};
    if (seqRaw is Map) {
      for (final entry in seqRaw.entries) {
        final value = int.tryParse(entry.value.toString());
        if (value != null && value >= 0) {
          seqByScope[entry.key.toString()] = value;
        }
      }
    }

    return MobileE2ESnapshot(
      epoch: (json['epoch'] as num?)?.toInt() ?? 1,
      rootKey: rootKey,
      device: MobileDeviceIdentity.fromJson(deviceRaw.cast<String, dynamic>()),
      peers: peerMap,
      seqByScope: seqByScope,
    );
  }
}

class ScanExchangeKeyPair {
  const ScanExchangeKeyPair({
    required this.publicKey,
    required this.privateKey,
  });

  final String publicKey;
  final String privateKey;
}

class ScanBootstrapState {
  const ScanBootstrapState({
    required this.rootKey,
    required this.epoch,
    required this.hostDeviceId,
    required this.hostEncPublicKey,
    required this.hostSignPublicKey,
  });

  final String rootKey;
  final int epoch;
  final String hostDeviceId;
  final String hostEncPublicKey;
  final String hostSignPublicKey;
}

class MobileE2ERuntime {
  MobileE2ERuntime._({
    required SodiumSumo sodium,
    required MobileE2ESnapshot snapshot,
  })  : _sodium = sodium,
        _snapshot = snapshot;

  static Future<SodiumSumo>? _sodiumFuture;

  static Future<SodiumSumo> _resolveSodium() {
    final pending = _sodiumFuture;
    if (pending != null) {
      return pending;
    }
    final initialized = Future<SodiumSumo>.sync(SodiumSumoInit.init);
    _sodiumFuture = initialized;
    return initialized;
  }

  static Future<MobileE2ERuntime?> fromSnapshot(
    MobileE2ESnapshot? snapshot,
  ) async {
    if (snapshot == null ||
        snapshot.rootKey.trim().isEmpty ||
        snapshot.device.deviceId.trim().isEmpty ||
        snapshot.device.signPrivateKey.trim().isEmpty) {
      return null;
    }
    final sodium = await _resolveSodium();
    return MobileE2ERuntime._(sodium: sodium, snapshot: snapshot);
  }

  static Future<MobileDeviceIdentity> generateDeviceIdentity() async {
    final sodium = await _resolveSodium();
    final enc = sodium.crypto.kx.keyPair();
    final sign = sodium.crypto.sign.keyPair();
    try {
      return MobileDeviceIdentity(
        deviceId: 'mob_${_randomToken(10)}',
        encPublicKey: toBase64Url(enc.publicKey),
        encPrivateKey: toBase64Url(enc.secretKey.extractBytes()),
        signPublicKey: toBase64Url(sign.publicKey),
        signPrivateKey: toBase64Url(sign.secretKey.extractBytes()),
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
    } finally {
      enc.dispose();
      sign.dispose();
    }
  }

  static Future<ScanExchangeKeyPair> generateOneTimeScanExchangeKeyPair() async {
    final sodium = await _resolveSodium();
    final keyPair = sodium.crypto.kx.keyPair();
    try {
      return ScanExchangeKeyPair(
        publicKey: toBase64Url(keyPair.publicKey),
        privateKey: toBase64Url(keyPair.secretKey.extractBytes()),
      );
    } finally {
      keyPair.dispose();
    }
  }

  static Future<ScanBootstrapState> decryptScanBootstrap({
    required Map<String, dynamic> hostBundle,
    required String scanScope,
    required String mobileExchangePrivateKey,
    required String hostExchangePublicKey,
  }) async {
    final sodium = await _resolveSodium();
    final nonce = fromBase64Url(hostBundle['nonce']?.toString() ?? '');
    final aad = fromBase64Url(hostBundle['aad']?.toString() ?? '');
    final ciphertext = fromBase64Url(hostBundle['ciphertext']?.toString() ?? '');
    if (nonce.isEmpty || aad.isEmpty || ciphertext.isEmpty) {
      throw const E2ERuntimeException('e2e_scan_bundle_invalid');
    }

    if ((hostBundle['alg']?.toString() ?? '') != 'xchacha20poly1305') {
      throw const E2ERuntimeException('e2e_scan_bundle_alg_invalid');
    }

    final scope = scanScope;
    final expectedAad = utf8.encode(_canonicalize({'scope': scope, 'v': 1}));
    if (_constantTimeDiff(Uint8List.fromList(expectedAad), aad) != 0) {
      throw const E2ERuntimeException('e2e_scan_bundle_aad_invalid');
    }

    final scalar = SecureKey.fromList(
      sodium,
      fromBase64Url(mobileExchangePrivateKey),
    );
    SecureKey? sharedSecretKey;
    try {
      sharedSecretKey = sodium.crypto.scalarmult(
        n: scalar,
        p: fromBase64Url(hostExchangePublicKey),
      );
      final shared = sharedSecretKey.extractBytes();
      final keyBytes = _deriveScopedKey(
        rootKey: shared,
        epoch: 1,
        scope: scope,
        context: _scanExchangeContext,
      );
      final key = SecureKey.fromList(sodium, keyBytes);
      try {
        late final Uint8List plaintextBytes;
        try {
          plaintextBytes = sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
            cipherText: ciphertext,
            nonce: nonce,
            key: key,
            additionalData: aad,
          );
        } catch (_) {
          throw const E2ERuntimeException('e2e_scan_bundle_decrypt_failed');
        }
        final decoded =
            jsonDecode(utf8.decode(plaintextBytes)) as Map<String, dynamic>;
        final hostDevice =
            (decoded['hostDevice'] as Map?)?.cast<String, dynamic>() ?? {};
        final rootKey = decoded['rootKey']?.toString() ?? '';
        final epoch = (decoded['epoch'] as num?)?.toInt() ?? 1;
        final hostDeviceId = hostDevice['deviceId']?.toString() ?? '';
        final hostEncPublicKey = hostDevice['encPublicKey']?.toString() ?? '';
        final hostSignPublicKey = hostDevice['signPublicKey']?.toString() ?? '';
        if (rootKey.isEmpty ||
            hostDeviceId.isEmpty ||
            hostEncPublicKey.isEmpty ||
            hostSignPublicKey.isEmpty) {
          throw const E2ERuntimeException('e2e_scan_bundle_payload_invalid');
        }
        return ScanBootstrapState(
          rootKey: rootKey,
          epoch: max(1, epoch),
          hostDeviceId: hostDeviceId,
          hostEncPublicKey: hostEncPublicKey,
          hostSignPublicKey: hostSignPublicKey,
        );
      } finally {
        key.dispose();
      }
    } finally {
      scalar.dispose();
      sharedSecretKey?.dispose();
    }
  }

  final SodiumSumo _sodium;
  MobileE2ESnapshot _snapshot;
  final Map<String, int> _lastSeenByScopeSender = <String, int>{};

  MobileE2ESnapshot snapshot() {
    return MobileE2ESnapshot(
      epoch: _snapshot.epoch,
      rootKey: _snapshot.rootKey,
      device: _snapshot.device,
      peers: Map<String, MobilePeerDevice>.from(_snapshot.peers),
      seqByScope: Map<String, int>.from(_snapshot.seqByScope),
    );
  }

  bool get isReady {
    final device = _snapshot.device;
    return _snapshot.rootKey.trim().isNotEmpty &&
        device.deviceId.trim().isNotEmpty &&
        device.signPrivateKey.trim().isNotEmpty;
  }

  void addOrUpdatePeer(MobilePeerDevice peer) {
    if (peer.deviceId.trim().isEmpty || peer.signPublicKey.trim().isEmpty) {
      return;
    }
    final current = Map<String, MobilePeerDevice>.from(_snapshot.peers);
    current[peer.deviceId] = peer;
    _snapshot = MobileE2ESnapshot(
      epoch: _snapshot.epoch,
      rootKey: _snapshot.rootKey,
      device: _snapshot.device,
      peers: current,
      seqByScope: Map<String, int>.from(_snapshot.seqByScope),
    );
  }

  Map<String, dynamic> encryptEnvelope({
    required String scope,
    required String plaintext,
    Map<String, dynamic>? aadPayload,
  }) {
    if (!isReady) {
      throw const E2ERuntimeException('e2e_runtime_unavailable');
    }
    final seq = (_snapshot.seqByScope[scope] ?? 0) + 1;
    final nonce = _sodium.randombytes.buf(24);
    final aad = utf8.encode(_canonicalize(aadPayload ?? const {}));
    final keyBytes = _deriveScopedKey(
      rootKey: fromBase64Url(_snapshot.rootKey),
      epoch: _snapshot.epoch,
      scope: scope,
      context: _e2eEnvelopeContext,
    );

    final key = SecureKey.fromList(_sodium, keyBytes);
    Uint8List ciphertext;
    try {
      ciphertext = _sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
        message: Uint8List.fromList(utf8.encode(plaintext)),
        nonce: nonce,
        key: key,
        additionalData: Uint8List.fromList(aad),
      );
    } finally {
      key.dispose();
    }

    final payload = <String, dynamic>{
      'v': 1,
      'alg': 'xchacha20poly1305',
      'epoch': _snapshot.epoch,
      'senderDeviceId': _snapshot.device.deviceId,
      'seq': seq,
      'nonce': toBase64Url(nonce),
      'aad': toBase64Url(Uint8List.fromList(aad)),
      'ciphertext': toBase64Url(ciphertext),
    };
    final signature = _signPayload(payload, _snapshot.device.signPrivateKey);
    final updatedSeq = Map<String, int>.from(_snapshot.seqByScope);
    updatedSeq[scope] = seq;
    _snapshot = MobileE2ESnapshot(
      epoch: _snapshot.epoch,
      rootKey: _snapshot.rootKey,
      device: _snapshot.device,
      peers: Map<String, MobilePeerDevice>.from(_snapshot.peers),
      seqByScope: updatedSeq,
    );
    return {
      ...payload,
      'sig': signature,
    };
  }

  String decryptEnvelope({
    required String scope,
    required Map<String, dynamic> envelope,
  }) {
    if (!isReady) {
      throw const E2ERuntimeException('e2e_runtime_unavailable');
    }

    final payload = _normalizeEnvelopePayload(envelope);
    final senderDeviceId = payload['senderDeviceId']?.toString() ?? '';
    final seq = (payload['seq'] as num?)?.toInt() ?? -1;
    if (senderDeviceId.isEmpty || seq < 0) {
      throw const E2ERuntimeException('e2e_envelope_invalid');
    }

    final replayKey = '$scope:$senderDeviceId';
    final lastSeen = _lastSeenByScopeSender[replayKey] ?? -1;
    if (seq <= lastSeen) {
      throw const E2ERuntimeException('e2e_replay_detected');
    }

    final signature = envelope['sig']?.toString() ?? '';
    if (signature.isEmpty) {
      throw const E2ERuntimeException('e2e_missing_signature');
    }
    final signPublicKey = _resolveSignPublicKey(senderDeviceId);
    if (!_verifyPayload(payload, signature, signPublicKey)) {
      throw const E2ERuntimeException('e2e_invalid_signature');
    }

    final keyBytes = _deriveScopedKey(
      rootKey: fromBase64Url(_snapshot.rootKey),
      epoch: (payload['epoch'] as num?)?.toInt() ?? _snapshot.epoch,
      scope: scope,
      context: _e2eEnvelopeContext,
    );
    final nonce = fromBase64Url(payload['nonce']?.toString() ?? '');
    final aad = fromBase64Url(payload['aad']?.toString() ?? '');
    final ciphertext = fromBase64Url(payload['ciphertext']?.toString() ?? '');
    if (nonce.isEmpty || aad.isEmpty || ciphertext.isEmpty) {
      throw const E2ERuntimeException('e2e_envelope_invalid');
    }
    final key = SecureKey.fromList(_sodium, keyBytes);
    try {
      late final Uint8List plaintext;
      try {
        plaintext = _sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
          cipherText: ciphertext,
          nonce: nonce,
          key: key,
          additionalData: aad,
        );
      } catch (_) {
        throw const E2ERuntimeException('e2e_envelope_decrypt_failed');
      }
      _lastSeenByScopeSender[replayKey] = seq;
      return utf8.decode(plaintext);
    } finally {
      key.dispose();
    }
  }

  String _resolveSignPublicKey(String senderDeviceId) {
    if (senderDeviceId == _snapshot.device.deviceId) {
      return _snapshot.device.signPublicKey;
    }
    final peer = _snapshot.peers[senderDeviceId];
    if (peer == null || peer.signPublicKey.trim().isEmpty) {
      throw const E2ERuntimeException('e2e_unknown_sender_device');
    }
    return peer.signPublicKey;
  }

  String _signPayload(Map<String, dynamic> payload, String signPrivateKey) {
    final privateKey = SecureKey.fromList(_sodium, fromBase64Url(signPrivateKey));
    try {
      final encoded = Uint8List.fromList(utf8.encode(_canonicalize(payload)));
      final signature = _sodium.crypto.sign.detached(
        message: encoded,
        secretKey: privateKey,
      );
      return toBase64Url(signature);
    } finally {
      privateKey.dispose();
    }
  }

  bool _verifyPayload(
    Map<String, dynamic> payload,
    String sig,
    String signPublicKey,
  ) {
    final encoded = Uint8List.fromList(utf8.encode(_canonicalize(payload)));
    return _sodium.crypto.sign.verifyDetached(
      message: encoded,
      signature: fromBase64Url(sig),
      publicKey: fromBase64Url(signPublicKey),
    );
  }

  static Map<String, dynamic> _normalizeEnvelopePayload(Map<String, dynamic> raw) {
    final payload = <String, dynamic>{
      'v': (raw['v'] as num?)?.toInt(),
      'alg': raw['alg']?.toString(),
      'epoch': (raw['epoch'] as num?)?.toInt(),
      'senderDeviceId': raw['senderDeviceId']?.toString(),
      'seq': (raw['seq'] as num?)?.toInt(),
      'nonce': raw['nonce']?.toString(),
      'aad': raw['aad']?.toString(),
      'ciphertext': raw['ciphertext']?.toString(),
    };
    if (payload['v'] != 1 || payload['alg'] != 'xchacha20poly1305') {
      throw const E2ERuntimeException('e2e_envelope_invalid_alg');
    }
    if ((payload['nonce']?.toString() ?? '').isEmpty ||
        (payload['aad']?.toString() ?? '').isEmpty ||
        (payload['ciphertext']?.toString() ?? '').isEmpty) {
      throw const E2ERuntimeException('e2e_envelope_invalid');
    }
    return payload;
  }

  static Uint8List _deriveScopedKey({
    required Uint8List rootKey,
    required int epoch,
    required String scope,
    required String context,
  }) {
    final salt = Uint8List.fromList(utf8.encode('$context:epoch:$epoch'));
    final info = Uint8List.fromList(utf8.encode(scope));
    return _hkdfSha256(
      ikm: rootKey,
      salt: salt,
      info: info,
      length: 32,
    );
  }

  static Uint8List _hkdfSha256({
    required Uint8List ikm,
    required Uint8List salt,
    required Uint8List info,
    required int length,
  }) {
    final prk = crypto.Hmac(crypto.sha256, salt).convert(ikm).bytes;
    final hmac = crypto.Hmac(crypto.sha256, prk);
    final output = BytesBuilder(copy: false);
    var previous = Uint8List(0);
    var counter = 1;
    while (output.length < length) {
      final blockInput = BytesBuilder(copy: false)
        ..add(previous)
        ..add(info)
        ..add([counter]);
      previous = Uint8List.fromList(hmac.convert(blockInput.toBytes()).bytes);
      output.add(previous);
      counter += 1;
    }
    final bytes = output.toBytes();
    return Uint8List.fromList(bytes.sublist(0, length));
  }

  static int _constantTimeDiff(Uint8List left, Uint8List right) {
    if (left.length != right.length) {
      return 1;
    }
    var diff = 0;
    for (var index = 0; index < left.length; index += 1) {
      diff |= left[index] ^ right[index];
    }
    return diff;
  }

  static String _randomToken(int length) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return toBase64Url(Uint8List.fromList(bytes)).replaceAll('-', '').replaceAll('_', '');
  }
}

String toBase64Url(Uint8List value) {
  return base64UrlEncode(value).replaceAll('=', '');
}

Uint8List fromBase64Url(String value) {
  final normalized = value.trim().replaceAll('-', '+').replaceAll('_', '/');
  if (normalized.isEmpty) {
    return Uint8List(0);
  }
  final padded = normalized.padRight((normalized.length + 3) & ~3, '=');
  try {
    return Uint8List.fromList(base64Decode(padded));
  } catch (_) {
    return Uint8List(0);
  }
}

String _canonicalize(dynamic value) {
  if (value == null) {
    return 'null';
  }
  if (value is String || value is num || value is bool) {
    return jsonEncode(value);
  }
  if (value is List) {
    return '[${value.map(_canonicalize).join(',')}]';
  }
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((left, right) => left.key.toString().compareTo(right.key.toString()));
    final parts = <String>[];
    for (final entry in entries) {
      parts.add('${jsonEncode(entry.key.toString())}:${_canonicalize(entry.value)}');
    }
    return '{${parts.join(',')}}';
  }
  return jsonEncode(value.toString());
}
