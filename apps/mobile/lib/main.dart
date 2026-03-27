import 'package:flutter/material.dart';

import 'api.dart';

void main() {
  runApp(const NomadeApp());
}

class NomadeApp extends StatelessWidget {
  const NomadeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nomade for Codex',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final api = NomadeApi(baseUrl: 'http://localhost:8080');
  final emailController = TextEditingController();

  String status = 'Idle';
  String? deviceCode;
  String? userCode;
  String? accessToken;
  String? pairingCode;

  Future<void> runLoginFlow() async {
    setState(() => status = 'Requesting device code...');
    final started = await api.startDeviceCode();
    deviceCode = started['deviceCode'] as String;
    userCode = started['userCode'] as String;

    if (!mounted) {
      return;
    }

    setState(() => status = 'Approving code...');
    await api.approveDeviceCode(userCode: userCode!, email: emailController.text.trim());

    setState(() => status = 'Polling token...');
    while (mounted) {
      final polled = await api.pollDeviceCode(deviceCode!);
      if (polled['status'] == 'ok') {
        accessToken = polled['accessToken'] as String;
        setState(() => status = 'Authenticated');
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> makePairingCode() async {
    if (accessToken == null) {
      return;
    }
    setState(() => status = 'Creating pairing code...');
    final response = await api.createPairingCode(accessToken!);
    setState(() {
      pairingCode = response['pairingCode'] as String;
      status = 'Pairing code ready';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nomade for Codex')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: runLoginFlow,
              child: const Text('Login with Device Code'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: makePairingCode,
              child: const Text('Create Agent Pairing Code'),
            ),
            const SizedBox(height: 16),
            Text('Status: $status'),
            if (userCode != null) Text('User code: $userCode'),
            if (pairingCode != null) Text('Pairing code: $pairingCode'),
          ],
        ),
      ),
    );
  }
}
