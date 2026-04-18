import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/nomade_provider.dart';
import '../widgets/app_motion.dart';
import 'login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingData> _data = const [
    OnboardingData(
      stage: 'Fast Setup',
      title: 'Install and connect in minutes',
      description:
          'Nomade is ready after one browser sign-in. Keep the default endpoint for cloud, or switch to self-host in one tap.',
      icon: Icons.rocket_launch_rounded,
      chips: [
        'Cloud-ready',
        'Self-host compatible',
        'No desktop pairing required',
      ],
      highlights: [
        'Use the default endpoint for the quickest start.',
        'Bring your own API endpoint if you run Nomade yourself.',
        'Sync workspaces and conversations across desktop and mobile.',
      ],
      note:
          'You can edit the server endpoint at any time on the next sign-in screen.',
    ),
    OnboardingData(
      stage: 'Clear Steps',
      title: 'Know exactly what to do',
      description:
          'The app guides setup step by step, so new users and teams can onboard with minimal friction.',
      icon: Icons.route_rounded,
      chips: [
        '3-step flow',
        'Beginner friendly',
        'Works with secure scan',
      ],
      steps: [
        'Tap sign in to open browser authorization.',
        'Confirm the short code in browser to authorize this device.',
        'Optional: scan secure QR to provision encrypted device keys.',
      ],
      highlights: [
        'No hidden setup requirements before first use.',
        'Progress is visible so users always know what is next.',
      ],
      note:
          'If camera pairing is unavailable, browser login still gets you into Nomade.',
    ),
    OnboardingData(
      stage: 'Security',
      title: 'Understand the trust model',
      description:
          'Authentication and encryption setup are split on purpose, so account ownership and secure key provisioning stay explicit.',
      icon: Icons.shield_rounded,
      chips: [
        'Browser auth',
        'Device key provisioning',
        'Self-host support',
      ],
      highlights: [
        'Browser sign-in validates account ownership.',
        'Secure scan links your device encryption keys.',
        'Trusted dev mode is only for controlled private networks.',
      ],
      note:
          'This flow prevents ambiguous "magic login" while keeping setup understandable.',
    ),
    OnboardingData(
      stage: 'Operate',
      title: 'Run your workflow from one mobile cockpit',
      description:
          'Once signed in, monitor conversation execution, manage workspaces, and operate services without switching apps.',
      icon: Icons.hub_rounded,
      chips: [
        'Live turn status',
        'Workspace controls',
        'Service and tunnel visibility',
      ],
      highlights: [
        'Track ongoing turns and command output in real time.',
        'Manage services, logs, and preview tunnels from mobile.',
        'Copy useful debug logs in one tap when troubleshooting.',
      ],
      note: 'Open sign-in now to start setup.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isWide = MediaQuery.of(context).size.width >= 760;
    final isLastPage = _currentPage == _data.length - 1;

    return Scaffold(
      body: AppAmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              FadeSlideIn(
                delay: const Duration(milliseconds: 40),
                beginOffset: const Offset(0, -0.02),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      Container(
                        height: 36,
                        width: 36,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.32),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Nomade for Codex',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        child: Text(
                          'Step ${_currentPage + 1}/${_data.length}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!isLastPage) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _goToLogin,
                          child: const Text('Skip'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _data.length,
                  onPageChanged: (index) =>
                      setState(() => _currentPage = index),
                  itemBuilder: (context, index) => _OnboardingPage(
                    data: _data[index],
                    pageIndex: index,
                    pageCount: _data.length,
                    isWide: isWide,
                  ),
                ),
              ),
              FadeSlideIn(
                delay: const Duration(milliseconds: 120),
                beginOffset: const Offset(0, 0.02),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: AnimatedContainer(
                      duration: AppMotion.medium,
                      curve: AppMotion.standardCurve,
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.72),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _data[_currentPage].stage,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            alignment: WrapAlignment.center,
                            children: List.generate(
                              _data.length,
                              (index) => _ProgressPill(
                                active: _currentPage == index,
                                onTap: () => _goToPage(index),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              if (_currentPage > 0) ...[
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _goBack,
                                    icon: const Icon(Icons.arrow_back_rounded),
                                    label: const Text('Back'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _advance,
                                  icon: Icon(
                                    isLastPage
                                        ? Icons.login_rounded
                                        : Icons.arrow_forward_rounded,
                                  ),
                                  label: Text(
                                    isLastPage ? 'Open sign-in' : 'Continue',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (isLastPage) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _openSelfHostingDocs,
                              icon: const Icon(Icons.open_in_new_rounded),
                              label: const Text('Self-hosting docs'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _advance() {
    if (_currentPage < _data.length - 1) {
      _goToPage(_currentPage + 1);
      return;
    }
    _goToLogin();
  }

  void _goBack() {
    if (_currentPage == 0) {
      return;
    }
    _goToPage(_currentPage - 1);
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: AppMotion.medium,
      curve: AppMotion.standardCurve,
    );
  }

  Uri _publicUrlForApiBase(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final base = Uri.parse(context.read<NomadeProvider>().api.baseUrl);
    return base.replace(
      path: normalizedPath,
      queryParameters: null,
      fragment: null,
    );
  }

  Future<void> _openSelfHostingDocs() async {
    final uri = _publicUrlForApiBase('/docs/self-hosting');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open self-hosting docs.')),
      );
    }
  }

  void _goToLogin() {
    Navigator.pushReplacement(
      context,
      buildAppPageRoute(context, const LoginScreen()),
    );
  }
}

class OnboardingData {
  final String stage;
  final String title;
  final String description;
  final IconData icon;
  final List<String> chips;
  final List<String> highlights;
  final List<String> steps;
  final String note;

  const OnboardingData({
    required this.stage,
    required this.title,
    required this.description,
    required this.icon,
    required this.note,
    this.chips = const <String>[],
    this.highlights = const <String>[],
    this.steps = const <String>[],
  });
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.data,
    required this.pageIndex,
    required this.pageCount,
    required this.isWide,
  });

  final OnboardingData data;
  final int pageIndex;
  final int pageCount;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 26),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 820 : 560),
                child: FadeSlideIn(
                  key: ValueKey('${data.stage}-${data.title}'),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          scheme.primary.withValues(alpha: 0.28),
                          scheme.tertiary.withValues(alpha: 0.2),
                          scheme.surface.withValues(alpha: 0.7),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(1.2),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isWide ? 30 : 20,
                          vertical: isWide ? 28 : 22,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(27),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withValues(
                                      alpha: 0.14,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${data.stage.toUpperCase()} | ${pageIndex + 1}/$pageCount',
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  height: 48,
                                  width: 48,
                                  decoration: BoxDecoration(
                                    color:
                                        scheme.primary.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    data.icon,
                                    color: scheme.primary,
                                    size: 26,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              data.title,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.45,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              data.description,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.48,
                              ),
                            ),
                            if (data.chips.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: data.chips
                                    .map((chip) => _TagChip(label: chip))
                                    .toList(growable: false),
                              ),
                            ],
                            if (data.steps.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              _StepRail(steps: data.steps),
                            ],
                            if (data.highlights.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              Column(
                                children: data.highlights
                                    .map((item) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 10),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(
                                                Icons.check_circle_rounded,
                                                size: 18,
                                                color: scheme.primary,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  item,
                                                  style: theme
                                                      .textTheme.bodyMedium
                                                      ?.copyWith(
                                                    color:
                                                        scheme.onSurfaceVariant,
                                                    height: 1.45,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ))
                                    .toList(growable: false),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLow.withValues(
                                  alpha: 0.76,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: scheme.outlineVariant
                                      .withValues(alpha: 0.7),
                                ),
                              ),
                              child: Text(
                                data.note,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.68)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _StepRail extends StatelessWidget {
  const _StepRail({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        children: List.generate(
          steps.length,
          (index) => Padding(
            padding:
                EdgeInsets.only(bottom: index == steps.length - 1 ? 8 : 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 24,
                  width: 24,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      steps[index],
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressPill extends StatelessWidget {
  const _ProgressPill({
    required this.active,
    required this.onTap,
  });

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.medium,
        curve: AppMotion.standardCurve,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        height: 8,
        width: active ? 32 : 10,
        decoration: BoxDecoration(
          color: active ? scheme.primary : scheme.outlineVariant,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}
