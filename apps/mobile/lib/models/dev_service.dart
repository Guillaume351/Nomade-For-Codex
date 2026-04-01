class DevService {
  DevService({
    required this.id,
    required this.workspaceId,
    required this.agentId,
    required this.name,
    required this.role,
    required this.command,
    required this.cwd,
    required this.port,
    required this.healthPath,
    required this.envTemplate,
    required this.dependsOn,
    required this.autoTunnel,
    required this.state,
    required this.runtimeStatus,
    this.lastError,
    this.tunnel,
    this.session,
  });

  factory DevService.fromJson(Map<String, dynamic> json) {
    return DevService(
      id: (json['id'] ?? '').toString(),
      workspaceId: (json['workspaceId'] ?? '').toString(),
      agentId: (json['agentId'] ?? '').toString(),
      name: (json['name'] ?? 'service').toString(),
      role: (json['role'] ?? 'service').toString(),
      command: (json['command'] ?? '').toString(),
      cwd: json['cwd']?.toString(),
      port: (json['port'] as num?)?.toInt() ?? 0,
      healthPath: (json['healthPath'] ?? '/').toString(),
      envTemplate: ((json['envTemplate'] as Map?) ?? {})
          .map((key, value) => MapEntry(key.toString(), value.toString())),
      dependsOn: ((json['dependsOn'] as List?) ?? [])
          .map((item) => item.toString())
          .toList(),
      autoTunnel: json['autoTunnel'] == true,
      state: (json['state'] ?? 'stopped').toString(),
      runtimeStatus: (json['runtimeStatus'] ?? 'stopped').toString(),
      lastError: json['lastError']?.toString(),
      tunnel: json['tunnel'] is Map
          ? DevServiceTunnel.fromJson(
              (json['tunnel'] as Map).cast<String, dynamic>())
          : null,
      session: json['session'] is Map
          ? DevServiceSession.fromJson(
              (json['session'] as Map).cast<String, dynamic>())
          : null,
    );
  }

  final String id;
  final String workspaceId;
  final String agentId;
  final String name;
  final String role;
  final String command;
  final String? cwd;
  final int port;
  final String healthPath;
  final Map<String, String> envTemplate;
  final List<String> dependsOn;
  final bool autoTunnel;
  final String state;
  final String runtimeStatus;
  final String? lastError;
  final DevServiceTunnel? tunnel;
  final DevServiceSession? session;

  DevService copyWith({
    String? state,
    String? runtimeStatus,
    String? lastError,
    DevServiceTunnel? tunnel,
    DevServiceSession? session,
  }) {
    return DevService(
      id: id,
      workspaceId: workspaceId,
      agentId: agentId,
      name: name,
      role: role,
      command: command,
      cwd: cwd,
      port: port,
      healthPath: healthPath,
      envTemplate: envTemplate,
      dependsOn: dependsOn,
      autoTunnel: autoTunnel,
      state: state ?? this.state,
      runtimeStatus: runtimeStatus ?? this.runtimeStatus,
      lastError: lastError ?? this.lastError,
      tunnel: tunnel ?? this.tunnel,
      session: session ?? this.session,
    );
  }
}

class DevServiceTunnel {
  DevServiceTunnel({
    required this.id,
    required this.slug,
    required this.previewUrl,
    required this.tokenRequired,
    required this.isReachable,
    this.lastProbeAt,
    this.lastProbeStatus,
    this.lastError,
    this.lastProbeCode,
  });

  factory DevServiceTunnel.fromJson(Map<String, dynamic> json) {
    return DevServiceTunnel(
      id: (json['id'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
      previewUrl: (json['previewUrl'] ?? '').toString(),
      tokenRequired: json['tokenRequired'] == true,
      isReachable: json['isReachable'] == true,
      lastProbeAt: json['lastProbeAt'] != null
          ? DateTime.tryParse(json['lastProbeAt'].toString())
          : null,
      lastProbeStatus: json['lastProbeStatus']?.toString(),
      lastError: json['lastError']?.toString(),
      lastProbeCode: (json['lastProbeCode'] as num?)?.toInt(),
    );
  }

  final String id;
  final String slug;
  final String previewUrl;
  final bool tokenRequired;
  final bool isReachable;
  final DateTime? lastProbeAt;
  final String? lastProbeStatus;
  final String? lastError;
  final int? lastProbeCode;
}

class DevServiceSession {
  DevServiceSession({
    required this.id,
    required this.status,
    required this.cursor,
  });

  factory DevServiceSession.fromJson(Map<String, dynamic> json) {
    return DevServiceSession(
      id: (json['id'] ?? '').toString(),
      status: (json['status'] ?? 'unknown').toString(),
      cursor: (json['cursor'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String status;
  final int cursor;
}
