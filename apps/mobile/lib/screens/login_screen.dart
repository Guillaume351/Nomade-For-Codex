import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/nomade_provider.dart';
import '../widgets/app_motion.dart';
import '../widgets/server_endpoint_dialog.dart';
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

  Uri _publicUrlForApiBase(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final base = Uri.parse(context.read<NomadeProvider>().api.baseUrl);
    return base.replace(
      path: normalizedPath,
      queryParameters: null,
      fragment: null,
    );
  }

  Future<void> _openPolicyLink(String path, String label) async {
    final uri = _publicUrlForApiBase(path);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open $label.')),
      );
    }
  }

  Future<void> _editServerEndpoint() async {
    final provider = context.read<NomadeProvider>();
    final result = await showServerEndpointDialog(
      context,
      currentUrl: provider.apiBaseUrl,
      defaultUrl: provider.defaultApiBaseUrl,
      helperText:
          'Use your self-host endpoint to avoid Nomade cloud subscription limits.',
    );
    if (result == null || !mounted) {
      return;
    }
    final normalized = result.normalizedUrl;
    final current = provider.apiBaseUrl.replaceAll(RegExp(r'/$'), '');
    if (normalized == current) {
      return;
    }
    await provider.setApiBaseUrl(normalized, clearSession: false);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.isReset
              ? 'Server endpoint reset to ${provider.apiBaseUrl}'
              : 'Server endpoint set to ${provider.apiBaseUrl}',
        ),
      ),
    );
  }

  Future<void> _resetServerEndpoint() async {
    final provider = context.read<NomadeProvider>();
    if (provider.isUsingDefaultApiBaseUrl) {
      return;
    }
    await provider.resetApiBaseUrl(clearSession: false);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Server endpoint reset to ${provider.apiBaseUrl}'),
      ),
    );
  }

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
          buildAppPageRoute(context, const HomeScreen()),
        );
        return;
      }
      final message = provider.status.trim().isEmpty
          ? 'Authorization did not complete. Please retry.'
          : provider.status;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      setState(() {
        _showCode = false;
        _userCode = null;
        _verificationUri = null;
      });
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

  Future<void> _cancelLoginFlow() async {
    await context.read<NomadeProvider>().cancelLoginAttempt();
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
      _showCode = false;
      _userCode = null;
      _verificationUri = null;
    });
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
      buildAppPageRoute(context, const SecureScanCameraScreen()),
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
          content: Text(
            'Secure scan captured. Opening browser sign-in to finish setup.',
          ),
        ),
      );
      if (!_isLoading) {
        await _handleLogin();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      final rawMessage = error.toString();
      final mismatchMarker = 'scan_server_mismatch:';
      final mismatchIndex = rawMessage.indexOf(mismatchMarker);
      if (mismatchIndex >= 0) {
        final suggested = rawMessage
            .substring(mismatchIndex + mismatchMarker.length)
            .trim()
            .replaceAll(RegExp(r'^Exception:\s*'), '');
        if (suggested.isNotEmpty) {
          final shouldSwitch = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Use scanned server endpoint?'),
                  content: Text(
                    'This secure QR targets:\n$suggested\n\nSwitch endpoint now?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('Switch'),
                    ),
                  ],
                ),
              ) ??
              false;
          if (!mounted) {
            return;
          }
          if (shouldSwitch) {
            await context
                .read<NomadeProvider>()
                .setApiBaseUrl(suggested, clearSession: false);
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Server endpoint set to $suggested')),
            );
          }
          return;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid secure scan: $rawMessage')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: AppAmbientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: FadeSlideIn(
                  beginOffset: const Offset(0, 0.025),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.72),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 30,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: AnimatedSwitcher(
                      duration: AppMotion.medium,
                      switchInCurve: AppMotion.standardCurve,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.03),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
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
      ),
    );
  }

  Widget _buildStartStep(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final provider = context.watch<NomadeProvider>();
    final hasPendingScan =
        (provider.pendingScanPayload?.trim().isNotEmpty ?? false) ||
            (provider.pendingScanShortCode?.trim().isNotEmpty ?? false);
    final isSelfHost = provider.entitlementSource == 'self_host' ||
        provider.planCode == 'self_host';

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
          'Sign in via browser to authenticate your account. Secure scan links this phone to end-to-end encrypted conversations.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow.withValues(alpha: 0.74),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.62),
            ),
          ),
          child: Text(
            'Why both steps? Browser login proves account ownership. QR secure scan provisions encryption keys. QR-only sign-in is not available yet.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow.withValues(alpha: 0.74),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.62),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Server endpoint',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      provider.apiBaseUrl,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (isSelfHost)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Self-host mode detected: no Nomade subscription required on this endpoint.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Wrap(
                spacing: 4,
                children: [
                  if (!provider.isUsingDefaultApiBaseUrl)
                    TextButton(
                      onPressed: _isLoading ? null : _resetServerEndpoint,
                      child: const Text('Reset'),
                    ),
                  TextButton(
                    onPressed: _isLoading ? null : _editServerEndpoint,
                    child: const Text('Change'),
                  ),
                ],
              ),
            ],
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
              'Secure scan is ready. Sign-in will continue and the approval resumes automatically.',
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
              : const Text('Sign in via browser'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _handleScanInApp,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Scan secure QR'),
        ),
        const SizedBox(height: 12),
        Text(
          'By continuing, you can review how Nomade handles personal data.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: -2,
          children: [
            TextButton(
              onPressed: () => _openPolicyLink('/legal/privacy', 'privacy policy'),
              child: const Text('Privacy policy'),
            ),
            TextButton(
              onPressed: () => _openPolicyLink('/legal/terms', 'terms of service'),
              child: const Text('Terms'),
            ),
            TextButton(
              onPressed: () =>
                  _openPolicyLink('/legal/account-deletion', 'account deletion'),
              child: const Text('Delete account'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCodeStep(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final provider = context.watch<NomadeProvider>();
    final statusText = provider.status.trim().isEmpty
        ? 'Waiting for authorization...'
        : provider.status.trim();

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
          statusText,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    _verificationUri == null ? null : _openVerificationPage,
                child: const Text('Open browser again'),
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
              onPressed: _cancelLoginFlow,
              child: const Text('Cancel'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: const LinearProgressIndicator(minHeight: 8),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PulseDot(color: scheme.primary, size: 8),
            const SizedBox(width: 8),
            Text(
              'Waiting for approval',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
