import 'package:flutter/material.dart';

import '../providers/nomade_provider.dart';

enum ServerEndpointDialogAction {
  apply,
  reset,
}

class ServerEndpointDialogResult {
  const ServerEndpointDialogResult._({
    required this.action,
    required this.normalizedUrl,
  });

  final ServerEndpointDialogAction action;
  final String normalizedUrl;

  bool get isReset => action == ServerEndpointDialogAction.reset;

  factory ServerEndpointDialogResult.apply(String normalizedUrl) {
    return ServerEndpointDialogResult._(
      action: ServerEndpointDialogAction.apply,
      normalizedUrl: normalizedUrl,
    );
  }

  factory ServerEndpointDialogResult.reset(String normalizedUrl) {
    return ServerEndpointDialogResult._(
      action: ServerEndpointDialogAction.reset,
      normalizedUrl: normalizedUrl,
    );
  }
}

Future<ServerEndpointDialogResult?> showServerEndpointDialog(
  BuildContext context, {
  required String currentUrl,
  required String defaultUrl,
  required String helperText,
  String title = 'Set server endpoint',
}) async {
  final normalizedCurrent = NomadeProvider.normalizeApiBaseUrl(currentUrl);
  final normalizedDefault = NomadeProvider.normalizeApiBaseUrl(defaultUrl);
  final controller = TextEditingController(text: normalizedCurrent);
  String? validationError;

  final result = await showDialog<ServerEndpointDialogResult>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.url,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'API base URL',
                  hintText: 'https://app.example.com',
                  errorText: validationError,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                helperText,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              Text(
                'Default endpoint: $normalizedDefault',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            if (normalizedCurrent != normalizedDefault)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(
                  ServerEndpointDialogResult.reset(normalizedDefault),
                ),
                child: const Text('Reset'),
              ),
            FilledButton(
              onPressed: () {
                final raw = controller.text.trim();
                try {
                  final next = NomadeProvider.normalizeApiBaseUrl(raw);
                  Navigator.of(dialogContext).pop(
                    ServerEndpointDialogResult.apply(next),
                  );
                } on FormatException catch (error) {
                  setDialogState(() {
                    validationError = error.message;
                  });
                }
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      );
    },
  );

  controller.dispose();
  return result;
}
