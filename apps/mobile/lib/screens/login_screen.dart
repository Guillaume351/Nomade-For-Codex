import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/nomade_provider.dart';
import 'home_screen.dart';
import 'secure_scan_camera_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  String? _userCode;
  String? _verificationUri;
  bool _showCode = false;

  Future<void> _handleLogin() async {
    final provider = context.read<NomadeProvider>();
    setState(() => _isLoading = true);

    try {
      final res = await provider.startLogin();
      if (!mounted) {
        return;
      }

      setState(() {
        _userCode = res['userCode'];
        _verificationUri = res['verificationUriComplete'];
        _showCode = true;
      });

      await _openVerificationPage();
      await provider.waitForBrowserApproval();
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);

      if (mounted && provider.isAuthenticated) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openVerificationPage() async {
    final raw = _verificationUri?.trim() ?? '';
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      throw Exception('Invalid verification URL');
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw Exception('Unable to open browser');
    }
  }

  Future<void> _handleScanInApp() async {
    final result = await Navigator.of(context).push<SecureScanCameraResult>(
      MaterialPageRoute(
        builder: (_) => const SecureScanCameraScreen(),
      ),
    );
    if (!mounted || result == null || !result.hasData) {
      return;
    }
    try {
      await context.read<NomadeProvider>().stagePendingSecureScanData(
            scanPayload: result.scanPayload,
            scanShortCode: result.scanShortCode,
            serverUrl: result.serverUrl,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Secure scan captured. Sign in to complete approval.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid secure scan: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.primary.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.2 : 0.12),
              theme.scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.93),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.7)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _showCode
                        ? _buildCodeStep(context)
                        : _buildStartStep(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStartStep(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final provider = context.watch<NomadeProvider>();
    final hasPendingScan = (provider.pendingScanPayload?.trim().isNotEmpty ??
            false) ||
        (provider.pendingScanShortCode?.trim().isNotEmpty ?? false);

    return Column(
      key: const ValueKey('email-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 56,
          width: 56,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(Icons.lock_open_rounded, color: scheme.primary, size: 30),
        ),
        const SizedBox(height: 18),
        Text(
          'Sign in to your Nomade account',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Open your browser to confirm login, then come back here while we complete authorization.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        if (hasPendingScan)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.44),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'A secure scan is pending and will resume automatically after sign-in.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: _isLoading ? null : _handleLogin,
          child: _isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Open browser login'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _handleScanInApp,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Scan secure login QR'),
        ),
      ],
    );
  }

  Widget _buildCodeStep(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      key: const ValueKey('code-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Confirm login',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Use this temporary code in your browser if prompted, then approve access.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Text(
            _userCode ?? '',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 4,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Waiting for authorization...',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _verificationUri == null ? null : _openVerificationPage,
          child: const Text('Open browser again'),
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: const LinearProgressIndicator(minHeight: 8),
        ),
      ],
    );
  }
}
