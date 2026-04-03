class TunnelDiagnostic {
  TunnelDiagnostic({
    required this.code,
    required this.message,
    required this.scope,
    this.at,
  });

  factory TunnelDiagnostic.fromJson(Map<String, dynamic> json) {
    return TunnelDiagnostic(
      code: (json['code'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      scope: (json['scope'] ?? 'transport').toString(),
      at: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString())
          : null,
    );
  }

  final String code;
  final String message;
  final String scope;
  final DateTime? at;
}

class TunnelPreview {
  TunnelPreview({
    required this.id,
    this.serviceId,
    required this.slug,
    required this.targetPort,
    required this.status,
    required this.tokenRequired,
    required this.previewUrl,
    required this.isReachable,
    this.lastProbeAt,
    this.lastProbeStatus,
    this.lastError,
    this.lastProbeCode,
    this.diagnostic,
  });

  factory TunnelPreview.fromJson(Map<String, dynamic> json) {
    return TunnelPreview(
      id: (json['id'] ?? '').toString(),
      serviceId: json['serviceId']?.toString(),
      slug: (json['slug'] ?? '').toString(),
      targetPort: (json['targetPort'] as num?)?.toInt() ?? 0,
      status: (json['status'] ?? 'unknown').toString(),
      tokenRequired: json['tokenRequired'] == true,
      previewUrl: (json['previewUrl'] ?? '').toString(),
      isReachable: json['isReachable'] == true,
      lastProbeAt: json['lastProbeAt'] != null
          ? DateTime.tryParse(json['lastProbeAt'].toString())
          : null,
      lastProbeStatus: json['lastProbeStatus']?.toString(),
      lastError: json['lastError']?.toString(),
      lastProbeCode: (json['lastProbeCode'] as num?)?.toInt(),
      diagnostic: json['diagnostic'] is Map<String, dynamic>
          ? TunnelDiagnostic.fromJson(
              json['diagnostic'] as Map<String, dynamic>,
            )
          : json['diagnostic'] is Map
              ? TunnelDiagnostic.fromJson(
                  (json['diagnostic'] as Map).cast<String, dynamic>(),
                )
              : null,
    );
  }

  final String id;
  final String? serviceId;
  final String slug;
  final int targetPort;
  final String status;
  final bool tokenRequired;
  final String previewUrl;
  final bool isReachable;
  final DateTime? lastProbeAt;
  final String? lastProbeStatus;
  final String? lastError;
  final int? lastProbeCode;
  final TunnelDiagnostic? diagnostic;

  TunnelPreview copyWith({
    String? status,
    bool? isReachable,
    String? lastProbeStatus,
    String? lastError,
    int? lastProbeCode,
    DateTime? lastProbeAt,
    TunnelDiagnostic? diagnostic,
    bool replaceDiagnostic = false,
  }) {
    return TunnelPreview(
      id: id,
      serviceId: serviceId,
      slug: slug,
      targetPort: targetPort,
      status: status ?? this.status,
      tokenRequired: tokenRequired,
      previewUrl: previewUrl,
      isReachable: isReachable ?? this.isReachable,
      lastProbeAt: lastProbeAt ?? this.lastProbeAt,
      lastProbeStatus: lastProbeStatus ?? this.lastProbeStatus,
      lastError: lastError ?? this.lastError,
      lastProbeCode: lastProbeCode ?? this.lastProbeCode,
      diagnostic: replaceDiagnostic ? diagnostic : this.diagnostic,
    );
  }
}
