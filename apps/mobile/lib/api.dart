import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class NomadeApi {
  NomadeApi({required this.baseUrl});

  final String baseUrl;

  Future<Map<String, dynamic>> startDeviceCode() async {
    final response = await http.post(Uri.parse('$baseUrl/auth/device/start'));
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> approveDeviceCode({
    required String userCode,
    required String email,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/device/approve'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'userCode': userCode, 'email': email}),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> pollDeviceCode(String deviceCode) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/device/poll'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'deviceCode': deviceCode}),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createPairingCode(String accessToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/agents/pair'),
      headers: {'authorization': 'Bearer $accessToken'},
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listAgents(String accessToken) async {
    final response = await http.get(
      Uri.parse('$baseUrl/agents'),
      headers: {'authorization': 'Bearer $accessToken'},
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return ((payload['items'] as List?) ?? [])
        .cast<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  Future<List<Map<String, dynamic>>> listWorkspaces(String accessToken) async {
    final response = await http.get(
      Uri.parse('$baseUrl/workspaces'),
      headers: {'authorization': 'Bearer $accessToken'},
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return ((payload['items'] as List?) ?? [])
        .cast<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, dynamic>> createWorkspace({
    required String accessToken,
    required String agentId,
    required String name,
    required String path,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/workspaces'),
      headers: {
        'authorization': 'Bearer $accessToken',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'agentId': agentId,
        'name': name,
        'path': path,
      }),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listConversations({
    required String accessToken,
    required String workspaceId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/conversations?workspaceId=$workspaceId'),
      headers: {'authorization': 'Bearer $accessToken'},
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return ((payload['items'] as List?) ?? [])
        .cast<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, dynamic>> createConversation({
    required String accessToken,
    required String workspaceId,
    required String agentId,
    required String title,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/conversations'),
      headers: {
        'authorization': 'Bearer $accessToken',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'workspaceId': workspaceId,
        'agentId': agentId,
        'title': title,
      }),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listConversationTurns({
    required String accessToken,
    required String conversationId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/conversations/$conversationId/turns'),
      headers: {'authorization': 'Bearer $accessToken'},
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return ((payload['items'] as List?) ?? [])
        .cast<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, dynamic>> createTurn({
    required String accessToken,
    required String conversationId,
    required String prompt,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/conversations/$conversationId/turns'),
      headers: {
        'authorization': 'Bearer $accessToken',
        'content-type': 'application/json',
      },
      body: jsonEncode({'prompt': prompt}),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> interruptTurn({
    required String accessToken,
    required String conversationId,
    required String turnId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/conversations/$conversationId/turns/$turnId/interrupt'),
      headers: {'authorization': 'Bearer $accessToken'},
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  WebSocketChannel openUserSocket(String accessToken) {
    final uri = Uri.parse(baseUrl.replaceFirst('http', 'ws'))
        .replace(path: '/ws', queryParameters: {'access_token': accessToken});
    return WebSocketChannel.connect(uri);
  }
}
