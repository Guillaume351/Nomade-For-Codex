import 'package:flutter_test/flutter_test.dart';
import 'package:nomade_mobile/providers/nomade/codex_utils.dart';
import 'package:nomade_mobile/providers/nomade_provider.dart';

void main() {
  group('NomadeProvider codex options normalization', () {
    test('normalizes modern collaboration mode payload and builds turn payload',
        () {
      final normalized =
          NomadeCodexUtils.normalizeCodexCollaborationModesPayload([
        {
          'name': 'Plan',
          'mode': 'plan',
          'reasoning_effort': 'medium',
        },
        {
          'name': 'Default',
          'mode': 'default',
        },
      ]);

      expect(
        normalized,
        contains(
          allOf([
            containsPair('slug', 'plan'),
            containsPair('mode', 'plan'),
          ]),
        ),
      );

      final payload = NomadeCodexUtils.buildSelectedCollaborationModePayload(
        collaborationModes: normalized,
        selectedSlug: 'plan',
      );
      expect(payload, isNotNull);
      expect(payload?['mode'], 'plan');
      expect(payload?['settings'], {'developer_instructions': null});
    });

    test('normalizes nested skills payload and keeps selected paths stable',
        () {
      final provider = NomadeProvider(baseUrl: 'https://api.example.com');
      provider.setSelectedSkillPaths([
        '/skills/a/SKILL.md',
        '/skills/missing/SKILL.md',
      ]);

      provider.applyCodexOptionsPayload({
        'models': const [],
        'approvalPolicies': const [],
        'sandboxModes': const [],
        'reasoningEfforts': const [],
        'collaborationModes': const [
          {'name': 'Default', 'mode': 'default'}
        ],
        'skills': [
          {
            'cwd': '/repo',
            'skills': [
              {
                'name': 'skill-a',
                'path': '/skills/a/SKILL.md',
                'description': 'Skill A',
                'scope': 'user',
                'enabled': true,
                'interface': {'shortDescription': 'short-a'},
              },
            ],
            'errors': const [],
          }
        ],
        'mcpServers': const [
          {
            'name': 'github',
            'enabled': true,
            'required': false,
            'authStatus': 'authorized',
            'toolCount': 8,
          }
        ],
        'defaults': const {},
      });

      expect(provider.codexSkills, hasLength(1));
      expect(provider.codexSkills.first['path'], '/skills/a/SKILL.md');
      expect(provider.codexSkills.first['shortDescription'], 'short-a');
      expect(provider.codexMcpServers, hasLength(1));
      expect(provider.codexMcpServers.first['name'], 'github');
      expect(provider.codexMcpServers.first['enabled'], isTrue);
      expect(provider.selectedSkillPaths, ['/skills/a/SKILL.md']);
      expect(provider.selectedCollaborationModeSlug, 'default');
    });

    test('drops legacy collaboration/skills payloads', () {
      final normalizedModes =
          NomadeCodexUtils.normalizeCodexCollaborationModesPayload([
        {
          'slug': 'legacy',
          'label': 'Legacy',
          'value': {
            'mode': 'default',
          },
        },
      ]);
      final normalizedSkills = NomadeCodexUtils.normalizeCodexSkillsPayload([
        {
          'name': 'legacy-skill',
          'path': '/skills/legacy/SKILL.md',
        },
      ]);

      expect(normalizedModes, isEmpty);
      expect(normalizedSkills, isEmpty);
    });
  });

  group('NomadeProvider slash command parsing', () {
    test('parses /plan and strips command from prompt', () {
      final result = NomadeCodexUtils.resolvePromptSlashCommand(
        '/plan Build an implementation checklist',
      );
      expect(result.commandDetected, isTrue);
      expect(result.collaborationModeKind, 'plan');
      expect(result.prompt, 'Build an implementation checklist');
    });

    test('parses /default command-only payload', () {
      final result = NomadeCodexUtils.resolvePromptSlashCommand('/default');
      expect(result.commandDetected, isTrue);
      expect(result.collaborationModeKind, 'default');
      expect(result.prompt, isEmpty);
    });

    test('parses /plan-mode and strips command from prompt', () {
      final result = NomadeCodexUtils.resolvePromptSlashCommand(
        '/plan-mode Draft rollout checklist',
      );
      expect(result.commandDetected, isTrue);
      expect(result.collaborationModeKind, 'plan');
      expect(result.prompt, 'Draft rollout checklist');
    });

    test('keeps unknown slash commands as plain prompt text', () {
      final result =
          NomadeCodexUtils.resolvePromptSlashCommand('/unknown test');
      expect(result.commandDetected, isFalse);
      expect(result.collaborationModeKind, isNull);
      expect(result.prompt, '/unknown test');
    });
  });
}
