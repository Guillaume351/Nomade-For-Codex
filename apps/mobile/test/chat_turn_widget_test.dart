import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomade_mobile/models/turn.dart';
import 'package:nomade_mobile/providers/nomade_provider.dart';
import 'package:nomade_mobile/widgets/chat_turn_widget.dart';
import 'package:provider/provider.dart';

class _SpyNomadeProvider extends NomadeProvider {
  _SpyNomadeProvider() : super(baseUrl: 'https://api.example.com');

  dynamic lastResult;
  String? lastError;

  @override
  void respondToServerRequest({
    required String conversationId,
    required String turnId,
    required String requestId,
    dynamic result,
    String? error,
  }) {
    lastResult = result;
    lastError = error;
  }
}

void main() {
  testWidgets('renders structured plan updates', (tester) async {
    final provider = _SpyNomadeProvider();
    final turn = Turn(
      id: 'turn-1',
      conversationId: 'conv-1',
      userPrompt: '',
      status: 'running',
      createdAt: DateTime.parse('2026-04-12T16:00:00Z'),
      updatedAt: DateTime.parse('2026-04-12T16:00:01Z'),
    );

    final timeline = provider.timelineForTurn(turn.id);
    final planItem = timeline.upsertItem(
      itemId: 'plan-turn-1',
      itemType: 'plan',
      stream: 'plan',
    );
    planItem.applyStarted(
      itemType: 'plan',
      payload: {
        'explanation': 'Ship plan mode safely',
        'plan': [
          {'step': 'Normalize options payloads', 'status': 'completed'},
          {'step': 'Render checklist UI', 'status': 'inProgress'},
        ],
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<NomadeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: ChatTurnWidget(turn: turn),
          ),
        ),
      ),
    );

    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Ship plan mode safely'), findsOneWidget);
    expect(find.text('Normalize options payloads'), findsOneWidget);
    expect(find.text('Render checklist UI'), findsOneWidget);
  });

  testWidgets('sends structured requestUserInput answers', (tester) async {
    final provider = _SpyNomadeProvider();
    final turn = Turn(
      id: 'turn-2',
      conversationId: 'conv-2',
      userPrompt: '',
      status: 'running',
      createdAt: DateTime.parse('2026-04-12T16:10:00Z'),
      updatedAt: DateTime.parse('2026-04-12T16:10:01Z'),
    );
    final timeline = provider.timelineForTurn(turn.id);
    final requestItem = timeline.upsertItem(
      itemId: 'server-request-req-1',
      itemType: 'serverRequest',
    );
    requestItem.applyStarted(
      itemType: 'serverRequest',
      payload: {
        'conversationId': 'conv-2',
        'turnId': 'turn-2',
        'requestId': 'req-1',
        'method': 'item/tool/requestUserInput',
        'params': {
          'questions': [
            {
              'id': 'scope',
              'header': 'Scope',
              'question': 'Choose the rollout scope',
              'isOther': true,
              'isSecret': false,
              'options': [
                {'label': 'Option A', 'description': 'First option'},
              ],
            }
          ],
        },
        'status': 'inProgress',
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<NomadeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: ChatTurnWidget(turn: turn),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Answer questions'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Option A'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(provider.lastError, isNull);
    expect(provider.lastResult, {
      'answers': {
        'scope': {
          'answers': ['Option A'],
        }
      }
    });
  });
}
