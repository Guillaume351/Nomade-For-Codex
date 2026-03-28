import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/nomade_provider.dart';
import '../screens/onboarding_screen.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NomadeProvider>();

    return Drawer(
      child: Column(
        children: [
          _buildHeader(context, provider),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildSectionHeader('Agents'),
                ...provider.agents.map((agent) => ListTile(
                      leading: Icon(
                        Icons.circle,
                        size: 12,
                        color: agent.isOnline ? Colors.green : Colors.grey,
                      ),
                      title: Text(agent.displayName),
                      selected: provider.selectedAgent?.id == agent.id,
                      onTap: () {
                        provider.selectedAgent = agent;
                        provider.loadWorkspacesForSelectedAgent();
                      },
                    )),
                const Divider(),
                _buildSectionHeader('Workspaces'),
                ...provider.workspaces.map((workspace) => ListTile(
                      leading: const Icon(Icons.folder_open_outlined, size: 20),
                      title: Text(workspace.name),
                      subtitle: Text(workspace.path,
                          style: const TextStyle(fontSize: 10)),
                      selected: provider.selectedWorkspace?.id == workspace.id,
                      onTap: () {
                        provider.selectedWorkspace = workspace;
                        provider.loadConversations();
                      },
                    )),
                const Divider(),
                _buildSectionHeader('Conversations'),
                ...provider.conversations.map((conv) => ListTile(
                      leading: const Icon(Icons.chat_outlined, size: 20),
                      title: Text(conv.title),
                      selected: provider.selectedConversation?.id == conv.id,
                      onTap: () {
                        provider.selectedConversation = conv;
                        provider.loadTurns(conv.id);
                        Navigator.pop(context); // Close drawer
                      },
                    )),
              ],
            ),
          ),
          _buildFooter(context, provider),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, NomadeProvider provider) {
    return DrawerHeader(
      decoration: BoxDecoration(color: Theme.of(context).primaryColor),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nomade',
            style: TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(
            'for Codex',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, NomadeProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey, width: 0.2)),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () async {
              await provider.logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
