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

  TunnelPreview copyWith({
    String? status,
    bool? isReachable,
    String? lastProbeStatus,
    String? lastError,
    int? lastProbeCode,
    DateTime? lastProbeAt,
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
    );
  }
}
