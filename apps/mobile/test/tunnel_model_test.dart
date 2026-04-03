import 'package:flutter_test/flutter_test.dart';
import 'package:nomade_mobile/models/tunnel.dart';

void main() {
  test('copyWith keeps diagnostic unless explicitly replaced', () {
    final base = TunnelPreview(
      id: 'tunnel-1',
      slug: 'slug-1',
      targetPort: 3000,
      status: 'open',
      tokenRequired: true,
      previewUrl: 'https://preview.localhost',
      isReachable: true,
      diagnostic: TunnelDiagnostic(
        code: 'agent_offline',
        message: 'Agent is offline',
        scope: 'transport',
      ),
    );

    final unchanged = base.copyWith(status: 'healthy');
    expect(unchanged.diagnostic?.code, 'agent_offline');

    final replaced = base.copyWith(
      replaceDiagnostic: true,
      diagnostic: null,
    );
    expect(replaced.diagnostic, isNull);
  });
}
