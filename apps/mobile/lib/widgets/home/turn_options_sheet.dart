import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/nomade_provider.dart';

class TurnOptionsSheet extends StatelessWidget {
  const TurnOptionsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NomadeProvider>();
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          10,
          24,
          MediaQuery.of(context).padding.bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Turn options',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tune model and execution policies for the next prompt.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            _buildDropdown(
              label: 'Model',
              value: provider.selectedModel,
              items: provider.codexModels
                  .map((m) => m['model'] as String)
                  .toList(growable: false),
              onChanged: (val) => provider.selectedModel = val,
            ),
            const SizedBox(height: 14),
            _buildDropdown(
              label: 'Approval policy',
              value: provider.selectedApprovalPolicy,
              items: provider.codexApprovalPolicies,
              onChanged: (val) => provider.selectedApprovalPolicy = val,
            ),
            const SizedBox(height: 14),
            _buildDropdown(
              label: 'Sandbox mode',
              value: provider.selectedSandboxMode,
              items: provider.codexSandboxModes,
              onChanged: (val) => provider.selectedSandboxMode = val,
            ),
            const SizedBox(height: 14),
            _buildDropdown(
              label: 'Reasoning effort',
              value: provider.selectedEffort,
              items: provider.codexReasoningEfforts,
              onChanged: (val) => provider.selectedEffort = val,
            ),
            const SizedBox(height: 14),
            _buildDropdown(
              label: 'Offline agent behavior',
              value: provider.offlineTurnDefault,
              items: const ['prompt', 'defer', 'fail'],
              onChanged: (val) {
                if (val == null) {
                  return;
                }
                provider.offlineTurnDefault = val;
              },
            ),
            if (!provider.canUseDeferredTurns) ...[
              const SizedBox(height: 8),
              Text(
                'Queued execution is unavailable on your current plan.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (provider.codexCollaborationModes.isNotEmpty) ...[
              const SizedBox(height: 14),
              _buildDropdown(
                label: 'Collaboration mode',
                value: provider.selectedCollaborationModeSlug,
                items: provider.codexCollaborationModes
                    .map((entry) => entry['slug']?.toString() ?? '')
                    .where((slug) => slug.isNotEmpty)
                    .toList(growable: false),
                onChanged: (val) =>
                    provider.selectedCollaborationModeSlug = val,
              ),
            ],
            if (provider.codexSkills.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Skills',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: provider.codexSkills.map((skill) {
                  final path = skill['path']?.toString() ?? '';
                  final name = skill['name']?.toString() ?? path;
                  if (path.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return FilterChip(
                    label: Text(name),
                    selected: provider.selectedSkillPaths.contains(path),
                    onSelected: (_) => provider.toggleSkillPath(path),
                  );
                }).toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    final sanitizedItems = items
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final currentValue =
        value != null && sanitizedItems.contains(value) ? value : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: currentValue,
          items: sanitizedItems
              .map((item) => DropdownMenuItem<String>(
                    value: item,
                    child: Text(item),
                  ))
              .toList(growable: false),
          onChanged: onChanged,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}
