import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class ApiException implements Exception {
  ApiException(
    this.message, {
    this.statusCode,
    this.errorCode,
    this.retryAfterSec,
  });

  final String message;
  final int? statusCode;
  final String? errorCode;
  final int? retryAfterSec;

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

    int? retryAfterSec;
    final retryAfterPayload = payload['retryAfterSec'];
    if (retryAfterPayload is num) {
      retryAfterSec = retryAfterPayload.toInt();
    } else if (retryAfterPayload is String) {
      retryAfterSec = int.tryParse(retryAfterPayload.trim());
    }
    retryAfterSec ??= int.tryParse(response.headers['retry-after'] ?? '');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final rawError = payload['error'];
      final reason = rawError is String && rawError.isNotEmpty
          ? rawError
          : (response.reasonPhrase ?? 'request_failed');
      throw ApiException(
        'API ${response.statusCode}: $reason',
        statusCode: response.statusCode,
        errorCode: rawError is String ? rawError : null,
        retryAfterSec: retryAfterSec,
      );
    }

    return payload;
  }

  Future<Map<String, dynamic>> startDeviceCode() async {
    final response = await _send(() => http.post(_uri('/auth/device/start')));
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> approveScanSecure({
    required String accessToken,
    String? scanPayload,
    String? scanShortCode,
    required Map<String, dynamic> mobileDevice,
  }) async {
    final body = <String, dynamic>{
      'mobileDevice': mobileDevice,
    };
    if (scanPayload != null && scanPayload.trim().isNotEmpty) {
      body['scanPayload'] = scanPayload.trim();
    }
    if (scanShortCode != null && scanShortCode.trim().isNotEmpty) {
      body['scanShortCode'] = scanShortCode.trim().toUpperCase();
    }
    final response = await _send(
      () => http.post(
        _uri('/auth/device/scan-approve'),
        headers: {
          'authorization': 'Bearer $accessToken',
          'content-type': 'application/json',
        },
        body: jsonEncode(body),
      ),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> scanMobileAck({
    required String accessToken,
    String? scanPayload,
    String? scanShortCode,
    bool ack = false,
  }) async {
    final body = <String, dynamic>{
      'ack': ack,
    };
    if (scanPayload != null && scanPayload.trim().isNotEmpty) {
      body['scanPayload'] = scanPayload.trim();
    }
    if (scanShortCode != null && scanShortCode.trim().isNotEmpty) {
      body['scanShortCode'] = scanShortCode.trim().toUpperCase();
    }
    final response = await _send(
      () => http.post(
        _uri('/auth/device/scan-mobile-ack'),
        headers: {
          'authorization': 'Bearer $accessToken',
          'content-type': 'application/json',
        },
        body: jsonEncode(body),
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

  Future<Map<String, dynamic>> getEntitlements(String accessToken) async {
    final response = await _send(
      () => http.get(
        _uri('/me/entitlements'),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
    );
    return _decodeObject(response);
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
    String? prompt,
    Map<String, dynamic>? e2ePromptEnvelope,
    List<Map<String, dynamic>>? inputItems,
    Map<String, dynamic>? collaborationMode,
    String? model,
    String? cwd,
    String? approvalPolicy,
    String? sandboxMode,
    String? effort,
  }) async {
    final body = <String, dynamic>{};
    final trimmedPrompt = prompt?.trim() ?? '';
    if (trimmedPrompt.isNotEmpty) {
      body['prompt'] = trimmedPrompt;
    }
    if (e2ePromptEnvelope != null && e2ePromptEnvelope.isNotEmpty) {
      body['e2ePromptEnvelope'] = e2ePromptEnvelope;
    }
    if (inputItems != null && inputItems.isNotEmpty) {
      body['inputItems'] = inputItems;
    }
    if (collaborationMode != null && collaborationMode.isNotEmpty) {
      body['collaborationMode'] = collaborationMode;
    }
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
    if (!body.containsKey('prompt') &&
        !body.containsKey('inputItems') &&
        !body.containsKey('e2ePromptEnvelope')) {
      throw ApiException('prompt/inputItems or e2ePromptEnvelope is required');
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

  Future<Map<String, dynamic>> createTunnel({
    required String accessToken,
    required String workspaceId,
    required String agentId,
    required int targetPort,
    String? serviceId,
    int? ttlSec,
  }) async {
    final body = <String, dynamic>{
      'workspaceId': workspaceId,
      'agentId': agentId,
      'targetPort': targetPort,
    };
    if (serviceId != null && serviceId.trim().isNotEmpty) {
      body['serviceId'] = serviceId.trim();
    }
    if (ttlSec != null && ttlSec > 0) {
      body['ttlSec'] = ttlSec;
    }
    final response = await _send(
      () => http.post(
        _uri('/tunnels'),
        headers: {
          'authorization': 'Bearer $accessToken',
          'content-type': 'application/json',
        },
        body: jsonEncode(body),
      ),
    );
    return _decodeObject(response);
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
