import 'package:flutter_test/flutter_test.dart';
import 'package:nomade_mobile/services/secure_scan_parser.dart';

void main() {
  group('parseSecureScanInput', () {
    test('parses nomade URI payload', () {
      const uri =
          'nomade://scan?server=https%3A%2F%2Fcontrol.example.com&scan_payload=abc.def.ghi&short_code=ab12cd34';
      final parsed = parseSecureScanInput(uri);
      expect(parsed, isNotNull);
      expect(parsed!.scanPayload, 'abc.def.ghi');
      expect(parsed.scanShortCode, 'AB12CD34');
      expect(parsed.serverUrl, 'https://control.example.com');
    });

    test('parses short code fallback', () {
      final parsed = parseSecureScanInput('ab 12-cd34');
      expect(parsed, isNotNull);
      expect(parsed!.scanPayload, isNull);
      expect(parsed.scanShortCode, 'AB12CD34');
    });

    test('parses raw payload token', () {
      final parsed = parseSecureScanInput('scan_payload_token_value');
      expect(parsed, isNotNull);
      expect(parsed!.scanPayload, 'scan_payload_token_value');
      expect(parsed.scanShortCode, isNull);
    });

    test('rejects empty input', () {
      expect(parseSecureScanInput('  '), isNull);
    });
  });
}
