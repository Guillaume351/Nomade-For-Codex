import 'package:flutter/material.dart';

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
      title: 'A cleaner way to run Codex from anywhere',
      description:
          'Nomade keeps your conversations, workspaces, and local agents in sync across desktop and mobile.',
      icon: Icons.explore_rounded,
    ),
    OnboardingData(
      title: 'Designed for live collaboration',
      description:
          'Track execution status in real time, follow command logs, and manage your active services without context switching.',
      icon: Icons.hub_rounded,
    ),
    OnboardingData(
      title: 'Secure by default, flexible for dev',
      description:
          'Use protected tunnel links in production and trusted mode for fast local previews when you control the network.',
      icon: Icons.verified_user_rounded,
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
    final isWide = MediaQuery.of(context).size.width >= 700;

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
                        height: 34,
                        width: 34,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Nomade for Codex',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (_currentPage < _data.length - 1)
                        TextButton(
                          onPressed: _goToLogin,
                          child: const Text('Skip'),
                        ),
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
                    constraints: const BoxConstraints(maxWidth: 620),
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
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              _data.length,
                              (index) => AnimatedContainer(
                                duration: AppMotion.medium,
                                curve: AppMotion.standardCurve,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                height: 7,
                                width: _currentPage == index ? 30 : 7,
                                decoration: BoxDecoration(
                                  color: _currentPage == index
                                      ? scheme.primary
                                      : scheme.outlineVariant,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _advance,
                            icon: Icon(
                              _currentPage == _data.length - 1
                                  ? Icons.rocket_launch_rounded
                                  : Icons.arrow_forward_rounded,
                            ),
                            label: Text(
                              _currentPage == _data.length - 1
                                  ? 'Get started'
                                  : 'Continue',
                            ),
                          ),
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
      _pageController.nextPage(
        duration: AppMotion.medium,
        curve: AppMotion.standardCurve,
      );
      return;
    }
    _goToLogin();
  }

  void _goToLogin() {
    Navigator.pushReplacement(
      context,
      buildAppPageRoute(context, const LoginScreen()),
    );
  }
}

class OnboardingData {
  final String title;
  final String description;
  final IconData icon;

  const OnboardingData({
    required this.title,
    required this.description,
    required this.icon,
  });
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.data,
    required this.isWide,
  });

  final OnboardingData data;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isWide ? 760 : 540),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: FadeSlideIn(
            key: ValueKey(data.title),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isWide ? 42 : 24,
                vertical: isWide ? 36 : 26,
              ),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.68),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.09),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: isWide ? 90 : 80,
                    width: isWide ? 90 : 80,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      data.icon,
                      size: isWide ? 42 : 36,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    data.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    data.description,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
