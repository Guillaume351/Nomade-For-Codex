import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomade_mobile/models/tunnel.dart';
import 'package:nomade_mobile/models/workspace.dart';
import 'package:nomade_mobile/providers/nomade_provider.dart';
import 'package:nomade_mobile/widgets/tunnel_manager_sheet.dart';
import 'package:provider/provider.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester,
    NomadeProvider provider,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<NomadeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showTunnelManagerSheet(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Workspace buildWorkspace() {
    return Workspace(
      id: 'workspace-1',
      agentId: 'agent-1',
      name: 'Workspace',
      path: '/tmp/workspace',
      createdAt: DateTime.parse('2026-04-02T10:00:00.000Z'),
    );
  }

  TunnelPreview buildTunnel({
    required TunnelDiagnostic diagnostic,
  }) {
    return TunnelPreview(
      id: 'tunnel-1',
      serviceId: 'service-1',
      slug: 'abc123',
      targetPort: 3000,
      status: 'unhealthy',
      tokenRequired: true,
      previewUrl: 'https://abc123.preview.localhost',
      isReachable: false,
      diagnostic: diagnostic,
    );
  }

  testWidgets('shows upstream app diagnostic banner', (tester) async {
    final provider = NomadeProvider(baseUrl: 'http://localhost:8080');
    final workspace = buildWorkspace();
    provider.workspaces = [workspace];
    provider.selectedWorkspace = workspace;
    provider.tunnels = [
      buildTunnel(
        diagnostic: TunnelDiagnostic(
          code: 'vite_svg_react_not_transformed',
          message: 'svg react mismatch',
          scope: 'upstream_app',
          at: DateTime.parse('2026-04-02T10:05:00.000Z'),
        ),
      ),
    ];

    await pumpDialog(tester, provider);

    expect(find.text('Proxied app runtime issue detected'), findsOneWidget);
    expect(find.textContaining('vite_svg_react_not_transformed'), findsWidgets);
    expect(find.text('Copy backend logs cmd'), findsOneWidget);
  });

  testWidgets('shows transport diagnostic banner', (tester) async {
    final provider = NomadeProvider(baseUrl: 'http://localhost:8080');
    final workspace = buildWorkspace();
    provider.workspaces = [workspace];
    provider.selectedWorkspace = workspace;
    provider.tunnels = [
      buildTunnel(
        diagnostic: TunnelDiagnostic(
          code: 'tunnel_ws_open_timeout',
          message: 'WebSocket upstream timed out while opening',
          scope: 'transport',
          at: DateTime.parse('2026-04-02T10:05:00.000Z'),
        ),
      ),
    ];

    await pumpDialog(tester, provider);

    expect(find.text('Tunnel transport issue detected'), findsOneWidget);
    expect(find.textContaining('tunnel_ws_open_timeout'), findsWidgets);
    expect(find.text('Copy agent logs cmd'), findsOneWidget);
  });
}
