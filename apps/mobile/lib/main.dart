import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/nomade_provider.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/app_motion.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => NomadeProvider(
            baseUrl: const String.fromEnvironment(
              'NOMADE_API_URL',
              defaultValue: 'http://localhost:8080',
            ),
          )..startup(),
        ),
      ],
      child: const NomadeApp(),
    ),
  );
}

class NomadeApp extends StatelessWidget {
  const NomadeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NomadeProvider>();

    return MaterialApp(
      title: 'Nomade for Codex',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      themeAnimationDuration: AppMotion.medium,
      themeAnimationCurve: AppMotion.standardCurve,
      scrollBehavior: const AppScrollBehavior(),
      home: provider.isAuthenticated
          ? const HomeScreen()
          : const OnboardingScreen(),
    );
  }
}
