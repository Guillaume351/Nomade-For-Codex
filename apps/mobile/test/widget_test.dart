import 'package:flutter_test/flutter_test.dart';

import 'package:nomade_mobile/main.dart';

void main() {
  testWidgets('Nomade app renders home title', (WidgetTester tester) async {
    await tester.pumpWidget(const NomadeApp());

    expect(find.text('Nomade for Codex'), findsOneWidget);
  });
}
