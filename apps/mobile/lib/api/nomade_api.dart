import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class ApiException implements Exception {
  ApiException(
    this.message, {
    this.statusCode,
    this.errorCode,
  });

  final String message;
  final int? statusCode;
  final String? errorCode;

  @override
  String toString() => message;
}

class NomadeApi {
  NomadeApi({required this.baseUrl});

  final String baseUrl;
  static const _requestTimeout = Duration(seconds: 12);

  Uri _uri(String path, {Map<String, String>? queryParameters}) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: path,
      queryParameters: queryParameters,
    );
  }

  Future<http.Response> _send(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request().timeout(_requestTimeout);
    } on TimeoutException {
      throw ApiException('Request timed out while contacting $baseUrl');
    } on http.ClientException catch (error) {
      throw ApiException('Network error: ${error.message}');
    }
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    final body = response.body.trim();
    Map<String, dynamic> payload = {};
    if (body.isNotEmpty) {
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw ApiException('Unexpected API response format');
      }
      payload = decoded.cast<String, dynamic>();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final rawError = payload['error'];
      final reason = rawError is String && rawError.isNotEmpty
          ? rawError
          : (response.reasonPhrase ?? 'request_failed');
      throw ApiException(
        'API ${response.statusCode}: $reason',
        statusCode: response.statusCode,
        errorCode: rawError is String ? rawError : null,
      );
    }

    return payload;
  }

  Future<Map<String, dynamic>> startDeviceCode() async {
    final response = await _send(() => http.post(_uri('/auth/device/start')));
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> approveDeviceCode({
    required String userCode,
    required String email,
  }) async {
    final response = await _send(
      () => http.post(
        _uri('/auth/device/approve'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'userCode': userCode, 'email': email}),
      ),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> pollDeviceCode(String deviceCode) async {
    final response = await _send(
      () => http.post(
        _uri('/auth/device/poll'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'deviceCode': deviceCode}),
      ),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> createPairingCode(String accessToken) async {
    final response = await _send(
      () => http.post(
        _uri('/agents/pair'),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> refreshAccessToken(String refreshToken) async {
    final response = await _send(
      () => http.post(
        _uri('/auth/refresh'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      ),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> logout({
    required String accessToken,
    required String refreshToken,
  }) async {
    final response = await _send(
      () => http.post(
        _uri('/auth/logout'),
        headers: {
          'authorization': 'Bearer $accessToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({'refreshToken': refreshToken}),
      ),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> importCodexThreads({
    required String accessToken,
    required String agentId,
    int limit = 500,
  }) async {
    final response = await _send(
      () => http.post(
        _uri('/agents/$agentId/codex/import'),
        headers: {
          'authorization': 'Bearer $accessToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({'limit': limit}),
      ),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getCodexOptions({
    required String accessToken,
    required String agentId,
    String? cwd,
  }) async {
    final query = <String, String>{};
    if (cwd != null && cwd.trim().isNotEmpty) {
      query['cwd'] = cwd.trim();
    }
    final response = await _send(
      () => http.get(
        _uri(
          '/agents/$agentId/codex/options',
          queryParameters: query.isEmpty ? null : query,
        ),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
    );
    return _decodeObject(response);
  }

  Future<List<Map<String, dynamic>>> listAgents(String accessToken) async {
    final response = await _send(
      () => http.get(
        _uri('/agents'),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
    );
    final payload = _decodeObject(response);
    return ((payload['items'] as List?) ?? [])
        .cast<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  Future<List<Map<String, dynamic>>> listWorkspaces(
    String accessToken, {
    String? agentId,
  }) async {
    final query = <String, String>{};
    if (agentId != null && agentId.trim().isNotEmpty) {
      query['agentId'] = agentId.trim();
    }
    final response = await _send(
      () => http.get(
        _uri('/workspaces', queryParameters: query.isEmpty ? null : query),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
    );
    final payload = _decodeObject(response);
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
    final response = await _send(
      () => http.post(
        _uri('/workspaces'),
        headers: {
          'authorization': 'Bearer $accessToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'agentId': agentId,
          'name': name,
          'path': path,
        }),
      ),
    );
    return _decodeObject(response);
  }

  Future<List<Map<String, dynamic>>> listConversations({
    required String accessToken,
    required String workspaceId,
  }) async {
    final response = await _send(
      () => http.get(
        _uri(
          '/conversations',
          queryParameters: {'workspaceId': workspaceId},
        ),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
    );
    final payload = _decodeObject(response);
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
    final response = await _send(
      () => http.post(
        _uri('/conversations'),
        headers: {
          'authorization': 'Bearer $accessToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'workspaceId': workspaceId,
          'agentId': agentId,
          'title': title,
        }),
      ),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getConversationTurns({
    required String accessToken,
    required String conversationId,
    bool forceHydrate = false,
  }) async {
    final query = forceHydrate ? <String, String>{'forceHydrate': '1'} : null;
    final response = await _send(
      () => http.get(
        _uri('/conversations/$conversationId/turns', queryParameters: query),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
    );
    return _decodeObject(response);
  }

  Future<List<Map<String, dynamic>>> listConversationTurns({
    required String accessToken,
    required String conversationId,
    bool forceHydrate = false,
  }) async {
    final payload = await getConversationTurns(
      accessToken: accessToken,
      conversationId: conversationId,
      forceHydrate: forceHydrate,
    );
    return ((payload['items'] as List?) ?? [])
        .cast<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, dynamic>> createTurn({
    required String accessToken,
    required String conversationId,
    required String prompt,
    String? model,
    String? cwd,
    String? approvalPolicy,
    String? sandboxMode,
    String? effort,
  }) async {
    final body = <String, dynamic>{'prompt': prompt};
    if (model != null && model.trim().isNotEmpty) {
      body['model'] = model.trim();
    }
    if (cwd != null && cwd.trim().isNotEmpty) {
      body['cwd'] = cwd.trim();
    }
    if (approvalPolicy != null && approvalPolicy.trim().isNotEmpty) {
      body['approvalPolicy'] = approvalPolicy.trim();
    }
    if (sandboxMode != null && sandboxMode.trim().isNotEmpty) {
      body['sandboxMode'] = sandboxMode.trim();
    }
    if (effort != null && effort.trim().isNotEmpty) {
      body['effort'] = effort.trim();
    }

    final response = await _send(
      () => http.post(
        _uri('/conversations/$conversationId/turns'),
        headers: {
          'authorization': 'Bearer $accessToken',
          'content-type': 'application/json',
        },
        body: jsonEncode(body),
      ),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> interruptTurn({
    required String accessToken,
    required String conversationId,
    required String turnId,
  }) async {
    final response = await _send(
      () => http.post(
        _uri('/conversations/$conversationId/turns/$turnId/interrupt'),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getWorkspaceDevSettings({
    required String accessToken,
    required String workspaceId,
  }) async {
    final response = await _send(
      () => http.get(
        _uri('/workspaces/$workspaceId/dev-settings'),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> updateWorkspaceDevSettings({
    required String accessToken,
    required String workspaceId,
    required bool trustedDevMode,
  }) async {
    final response = await _send(
      () => http.patch(
        _uri('/workspaces/$workspaceId/dev-settings'),
        headers: {
          'authorization': 'Bearer $accessToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({'trustedDevMode': trustedDevMode}),
      ),
    );
    return _decodeObject(response);
  }

  Future<List<Map<String, dynamic>>> listWorkspaceServices({
    required String accessToken,
    required String workspaceId,
  }) async {
    final response = await _send(
      () => http.get(
        _uri('/workspaces/$workspaceId/services'),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
    );
    final payload = _decodeObject(response);
    return ((payload['items'] as List?) ?? [])
        .cast<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, dynamic>> createWorkspaceService({
    required String accessToken,
    required String workspaceId,
    required Map<String, dynamic> body,
  }) async {
    final response = await _send(
      () => http.post(
        _uri('/workspaces/$workspaceId/services'),
        headers: {
          'authorization': 'Bearer $accessToken',
          'content-type': 'application/json',
        },
        body: jsonEncode(body),
      ),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> updateService({
    required String accessToken,
    required String serviceId,
    required Map<String, dynamic> body,
  }) async {
    final response = await _send(
      () => http.patch(
        _uri('/services/$serviceId'),
        headers: {
          'authorization': 'Bearer $accessToken',
          'content-type': 'application/json',
        },
        body: jsonEncode(body),
      ),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> startService({
    required String accessToken,
    required String serviceId,
  }) async {
    final response = await _send(
      () => http.post(
        _uri('/services/$serviceId/start'),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> stopService({
    required String accessToken,
    required String serviceId,
  }) async {
    final response = await _send(
      () => http.post(
        _uri('/services/$serviceId/stop'),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getServiceState({
    required String accessToken,
    required String serviceId,
  }) async {
    final response = await _send(
      () => http.get(
        _uri('/services/$serviceId/state'),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
    );
    return _decodeObject(response);
  }

  Future<List<Map<String, dynamic>>> listTunnels({
    required String accessToken,
    required String workspaceId,
  }) async {
    final response = await _send(
      () => http.get(
        _uri('/tunnels', queryParameters: {'workspaceId': workspaceId}),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
    );
    final payload = _decodeObject(response);
    return ((payload['items'] as List?) ?? [])
        .cast<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, dynamic>> issueTunnelToken({
    required String accessToken,
    required String tunnelId,
  }) async {
    final response = await _send(
      () => http.post(
        _uri('/tunnels/$tunnelId/issue-token'),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> rotateTunnelToken({
    required String accessToken,
    required String tunnelId,
  }) async {
    final response = await _send(
      () => http.post(
        _uri('/tunnels/$tunnelId/rotate-token'),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> deleteTunnel({
    required String accessToken,
    required String tunnelId,
  }) async {
    final response = await _send(
      () => http.delete(
        _uri('/tunnels/$tunnelId'),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
    );
    return _decodeObject(response);
  }

  WebSocketChannel openUserSocket(String accessToken) {
    final base = Uri.parse(baseUrl);
    final uri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws',
      queryParameters: {'access_token': accessToken},
    );
    return WebSocketChannel.connect(uri);
  }
}
