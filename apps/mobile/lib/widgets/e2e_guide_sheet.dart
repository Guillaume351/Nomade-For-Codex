import 'package:flutter/material.dart';

Future<void> showE2eGuideSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => const _E2eGuideSheet(),
  );
}

class _E2eGuideSheet extends StatelessWidget {
  const _E2eGuideSheet();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Guide E2E Dev (Tunnels + Services)',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Objectif: lancer backend + frontend à distance, avec URLs preview stables et expérience quasi locale.',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _step(
                context,
                '1. Préparer le workspace',
                'Pairer un agent, sélectionner le workspace, puis vérifier que le statut agent est online.',
              ),
              _step(
                context,
                '2. Configurer les services',
                'Créer au minimum un service backend (:8080) et un service frontend (:3000).',
              ),
              _step(
                context,
                '3. Lier front vers back via templates',
                'Dans envTemplate du frontend, utiliser \${service.backend.public_url} (ou public_origin/internal_url selon besoin).',
              ),
              _code(
                context,
                'Exemple envTemplate frontend',
                '{\n  "API_BASE_URL": "\${service.backend.public_url}"\n}',
              ),
              _step(
                context,
                '4. Démarrer les services',
                'Cliquer Start sur backend puis frontend (les dépendances peuvent être démarrées automatiquement).',
              ),
              _step(
                context,
                '5. Vérifier santé et tunnels',
                'Etat attendu: service healthy, tunnel reachable. Si unhealthy, vérifier healthPath et logs terminal.',
              ),
              _step(
                context,
                '6. Ouvrir la preview',
                'Dans Tunnels, utiliser Open preview. Si mode protégé, un token est émis automatiquement.',
              ),
              _step(
                context,
                '7. Itérer en live',
                'Utiliser le terminal service pour stdin/logs/stop, puis vérifier que les changements frontend/backend se reflètent via hot reload.',
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Sécurité: Trusted dev mode désactive la protection par token. À activer uniquement en environnement réseau maîtrisé.',
                  style: textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _step(BuildContext context, String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(content),
        ],
      ),
    );
  }

  Widget _code(BuildContext context, String title, String code) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              code,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
