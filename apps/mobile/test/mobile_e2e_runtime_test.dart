import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nomade_mobile/services/mobile_e2e_runtime.dart';

void main() {
  group('MobileE2ERuntime', () {
    test('encrypts and decrypts envelope', () async {
      final identity = await MobileE2ERuntime.generateDeviceIdentity();
      final snapshot = MobileE2ESnapshot(
        epoch: 1,
        rootKey: toBase64Url(Uint8List.fromList(List<int>.filled(32, 7))),
        device: identity,
        peers: const {},
        seqByScope: const {},
      );
      final runtime = await MobileE2ERuntime.fromSnapshot(snapshot);
      expect(runtime, isNotNull);

      final envelope = runtime!.encryptEnvelope(
        scope: 'conversation:conv_1',
        plaintext: '{"prompt":"hello"}',
      );

      final plaintext = runtime.decryptEnvelope(
        scope: 'conversation:conv_1',
        envelope: envelope,
      );
      expect(plaintext, '{"prompt":"hello"}');
    });

    test('rejects replayed envelope', () async {
      final identity = await MobileE2ERuntime.generateDeviceIdentity();
      final snapshot = MobileE2ESnapshot(
        epoch: 1,
        rootKey: toBase64Url(Uint8List.fromList(List<int>.filled(32, 13))),
        device: identity,
        peers: const {},
        seqByScope: const {},
      );
      final runtime = await MobileE2ERuntime.fromSnapshot(snapshot);
      expect(runtime, isNotNull);

      final envelope = runtime!.encryptEnvelope(
        scope: 'session:sess_1',
        plaintext: 'ls -la',
      );

      runtime.decryptEnvelope(scope: 'session:sess_1', envelope: envelope);
      expect(
        () => runtime.decryptEnvelope(scope: 'session:sess_1', envelope: envelope),
        throwsA(
          predicate(
            (error) =>
                error is E2ERuntimeException &&
                error.code == 'e2e_replay_detected',
          ),
        ),
      );
    });
  });
}
