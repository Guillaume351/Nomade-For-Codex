import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/secure_scan_parser.dart';

class SecureScanCameraResult {
  const SecureScanCameraResult({
    this.scanPayload,
    this.scanShortCode,
    this.serverUrl,
  });

  final String? scanPayload;
  final String? scanShortCode;
  final String? serverUrl;

  bool get hasData {
    return (scanPayload != null && scanPayload!.trim().isNotEmpty) ||
        (scanShortCode != null && scanShortCode!.trim().isNotEmpty);
  }
}

class SecureScanCameraScreen extends StatefulWidget {
  const SecureScanCameraScreen({
    super.key,
    this.title = 'Scan secure login QR',
  });

  final String title;

  @override
  State<SecureScanCameraScreen> createState() => _SecureScanCameraScreenState();
}

class _SecureScanCameraScreenState extends State<SecureScanCameraScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;
  String? _scanError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw == null || raw.isEmpty) {
        continue;
      }
      final parsed = parseSecureScanInput(raw);
      if (parsed == null || !parsed.hasData) {
        setState(() {
          _scanError = 'Invalid QR payload. Scan a Nomade secure login code.';
        });
        continue;
      }
      _handled = true;
      await _controller.stop();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(
        SecureScanCameraResult(
          scanPayload: parsed.scanPayload,
          scanShortCode: parsed.scanShortCode,
          serverUrl: parsed.serverUrl,
        ),
      );
      return;
    }
  }

  Future<void> _openManualFallback() async {
    final payloadController = TextEditingController();
    final shortCodeController = TextEditingController();
    try {
      final result = await showDialog<SecureScanCameraResult>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Enter scan code manually'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: payloadController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Scan payload',
                    hintText: 'nomade://scan?... or token',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: shortCodeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Fallback short code',
                    hintText: 'ABCD1234',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final payloadRaw = payloadController.text.trim();
                  final shortCodeRaw = shortCodeController.text.trim();
                  ParsedSecureScan? parsed;
                  if (payloadRaw.isNotEmpty) {
                    parsed = parseSecureScanInput(payloadRaw);
                  }
                  if ((parsed == null || !parsed.hasData) &&
                      shortCodeRaw.isNotEmpty) {
                    parsed = parseSecureScanInput(shortCodeRaw);
                  }
                  if (parsed == null || !parsed.hasData) {
                    Navigator.of(dialogContext).pop(
                      const SecureScanCameraResult(),
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                    SecureScanCameraResult(
                      scanPayload: parsed.scanPayload,
                      scanShortCode: parsed.scanShortCode,
                      serverUrl: parsed.serverUrl,
                    ),
                  );
                },
                child: const Text('Use this code'),
              ),
            ],
          );
        },
      );
      if (!mounted || result == null) {
        return;
      }
      if (!result.hasData) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid secure scan input')),
        );
        return;
      }
      Navigator.of(context).pop(result);
    } finally {
      payloadController.dispose();
      shortCodeController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Manual code entry',
            onPressed: _openManualFallback,
            icon: const Icon(Icons.keyboard_alt_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.42),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.5),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 26,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Scan the QR shown in terminal.',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'If camera access is denied or unavailable, use manual code entry.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (_scanError != null && _scanError!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _scanError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
