import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:nomade_mobile/main.dart';
import 'package:nomade_mobile/providers/nomade_provider.dart';

void main() {
  testWidgets('Nomade app renders onboarding screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => NomadeProvider(baseUrl: 'http://localhost:8080'),
        child: const NomadeApp(),
      ),
    );

    expect(find.text('Welcome to Nomade'), findsOneWidget);
  });
}
