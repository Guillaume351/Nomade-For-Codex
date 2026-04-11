import 'package:flutter_test/flutter_test.dart';
import 'package:nomade_mobile/models/agent.dart';
import 'package:nomade_mobile/models/conversation.dart';
import 'package:nomade_mobile/models/turn.dart';
import 'package:nomade_mobile/models/turn_item.dart';
import 'package:nomade_mobile/models/workspace.dart';
import 'package:nomade_mobile/providers/nomade_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NomadeProvider debug report', () {
    test('includes support sections and turn/timeline snapshots', () {
      final provider = NomadeProvider(baseUrl: 'https://api.example.com');
      provider.status = 'running';

      final agent = Agent(
        id: 'agent-1',
        displayName: 'MacBook-Pro',
        isOnline: true,
        createdAt: DateTime.parse('2026-04-11T19:00:00Z'),
      );
      final workspace = Workspace(
        id: 'ws-1',
        agentId: 'agent-1',
        name: 'Workspace',
        path: '/Users/guillaume/project',
        createdAt: DateTime.parse('2026-04-11T19:00:00Z'),
      );
      final conversation = Conversation(
        id: 'conv-1',
        userId: 'user-1',
        workspaceId: 'ws-1',
        agentId: 'agent-1',
        title: 'Debug',
        status: 'running',
        codexThreadId: 'thread-1',
        createdAt: DateTime.parse('2026-04-11T19:10:00Z'),
        updatedAt: DateTime.parse('2026-04-11T19:12:00Z'),
      );
      provider.agents = [agent];
      provider.workspaces = [workspace];
      provider.conversations = [conversation];
      provider.selectedAgent = agent;
      provider.selectedWorkspace = workspace;
      provider.selectedConversation = conversation;
      provider.selectedModel = 'gpt-5';
      provider.selectedApprovalPolicy = 'on-request';
      provider.selectedSandboxMode = 'workspace-write';
      provider.selectedEffort = 'medium';
      provider.selectedCollaborationModeSlug = 'default';
      provider.setSelectedSkillPaths(['/skills/e2e.md']);
      provider.codexRateLimitsByLimitId = {
        'codex': {
          'limitId': 'codex',
          'primary': {
            'usedPercent': 30,
            'remainingPercent': 70,
            'windowDurationMins': 300,
            'resetAt': '2026-04-11T23:00:00Z',
          },
          'secondary': {
            'usedPercent': 10,
            'remainingPercent': 90,
            'windowDurationMins': 10080,
            'resetAt': '2026-04-18T23:00:00Z',
          },
        },
      };

      final runningTurn = Turn(
        id: 'turn-1',
        conversationId: conversation.id,
        userPrompt: 'hello',
        codexTurnId: 'codex-turn-1',
        status: 'running',
        createdAt: DateTime.parse('2026-04-11T19:11:00Z'),
        updatedAt: DateTime.parse('2026-04-11T19:11:05Z'),
        items: [
          TurnItem(
            id: 'item-row-1',
            turnId: 'turn-1',
            itemId: 'item-1',
            itemType: 'commandExecution',
            ordinal: 1,
            payload: const {'status': 'inProgress'},
            createdAt: DateTime.parse('2026-04-11T19:11:01Z'),
          ),
        ],
      );
      final previousTurn = Turn(
        id: 'turn-0',
        conversationId: conversation.id,
        userPrompt: 'previous',
        codexTurnId: 'codex-turn-0',
        status: 'completed',
        createdAt: DateTime.parse('2026-04-11T19:00:00Z'),
        updatedAt: DateTime.parse('2026-04-11T19:00:03Z'),
        completedAt: DateTime.parse('2026-04-11T19:00:03Z'),
      );
      provider.turns = [runningTurn, previousTurn];
      provider.activeTurnId = runningTurn.id;

      final timeline = provider.timelineForTurn(runningTurn.id);
      final item = timeline.upsertItem(
        itemId: 'item-1',
        itemType: 'commandExecution',
        stream: 'commandExecution',
      );
      item.applyStarted(
        itemType: 'commandExecution',
        payload: const {'command': 'npm run build'},
      );
      item.applyCompleted(
        itemType: 'commandExecution',
        payload: const {
          'status': 'completed',
          'exitCode': 0,
          'durationMs': 1500,
        },
      );

      final report = provider.buildConversationDebugReport(conversation.id);

      expect(report, contains('supportBundleVersion=1'));
      expect(report, contains('[context]'));
      expect(report, contains('[security]'));
      expect(report, contains('[runtime]'));
      expect(report, contains('[events]'));
      expect(report, contains('[turns]'));
      expect(report, contains('[timeline]'));
      expect(report, contains('conversationId=conv-1'));
      expect(report, contains('turn[0]='));
      expect(report, contains('item[0]='));
      expect(report, contains('itemType=commandExecution'));
      expect(report, contains('codexRatePrimaryWindowMins=300'));
      expect(report, contains('codexRateSecondaryWindowMins=10080'));
    });

    test('redacts secrets while keeping diagnostic identifiers', () {
      final provider = NomadeProvider(
        baseUrl:
            'https://alice:pwd123@api.example.com/control?access_token=abcd1234&mode=prod',
      );
      provider.status =
          'Authorization: Bearer abcdefghijklmnop.qrstuvwxyzABCDEFG.hijklmnopqrstuv';

      final conversation = Conversation(
        id: 'conv-redact',
        userId: 'user-1',
        workspaceId: 'ws-1',
        agentId: 'agent-1',
        title: 'Redact',
        status: 'queued',
        codexThreadId: 'thread-redact',
        createdAt: DateTime.parse('2026-04-11T19:00:00Z'),
        updatedAt: DateTime.parse('2026-04-11T19:00:00Z'),
      );
      provider.conversations = [conversation];
      provider.selectedConversation = conversation;
      provider.turns = [
        Turn(
          id: 'turn-redact',
          conversationId: conversation.id,
          userPrompt: 'test',
          status: 'queued',
          error: 'refreshToken=tok_supersecret_123456',
          createdAt: DateTime.parse('2026-04-11T19:00:00Z'),
          updatedAt: DateTime.parse('2026-04-11T19:00:01Z'),
        ),
      ];
      final report = provider.buildConversationDebugReport(conversation.id);

      expect(report, contains('conversationId=conv-redact'));
      expect(report, contains('[REDACTED]'));
      expect(report, isNot(contains('pwd123')));
      expect(report, isNot(contains('access_token=abcd1234')));
      expect(report, isNot(contains('Bearer abcdefghijklmnop')));
      expect(report, isNot(contains('tok_supersecret_123456')));
    });

    test('handles missing conversation and empty events safely', () {
      final provider = NomadeProvider(baseUrl: 'https://api.example.com');

      final report = provider.buildConversationDebugReport('conv-missing');

      expect(report, contains('conversationId=conv-missing'));
      expect(report, contains('[events]'));
      expect(report, contains('count=0'));
      expect(report, contains('[turns]'));
      expect(report, contains('[timeline]'));
      expect(report, contains('turnId=-'));
    });
  });
}
