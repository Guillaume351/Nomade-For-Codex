class ParsedSecureScan {
  const ParsedSecureScan({
    this.scanPayload,
    this.scanShortCode,
    this.serverUrl,
  });

  final String? scanPayload;
  final String? scanShortCode;
  final String? serverUrl;

  bool get hasData {
    return (scanPayload != null && scanPayload!.trim().isNotEmpty) ||
        (scanShortCode != null && scanShortCode!.trim().isNotEmpty);
  }
}

ParsedSecureScan? parseSecureScanInput(String rawValue) {
  final raw = rawValue.trim();
  if (raw.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(raw);
  if (uri != null && uri.scheme == 'nomade') {
    final payload = _normalizePayload(uri.queryParameters['scan_payload']);
    final shortCode = _normalizeShortCode(uri.queryParameters['short_code']);
    final serverUrl = _normalizeServerUrl(uri.queryParameters['server']);
    if (payload == null && shortCode == null) {
      return null;
    }
    return ParsedSecureScan(
      scanPayload: payload,
      scanShortCode: shortCode,
      serverUrl: serverUrl,
    );
  }

  final asUrl = Uri.tryParse(raw);
  if (asUrl != null &&
      (asUrl.scheme == 'http' || asUrl.scheme == 'https') &&
      asUrl.queryParameters.isNotEmpty) {
    final payload = _normalizePayload(asUrl.queryParameters['scan_payload']);
    final shortCode = _normalizeShortCode(asUrl.queryParameters['short_code']);
    if (payload != null || shortCode != null) {
      final serverOrigin =
          '${asUrl.scheme}://${asUrl.host}${asUrl.hasPort ? ':${asUrl.port}' : ''}';
      return ParsedSecureScan(
        scanPayload: payload,
        scanShortCode: shortCode,
        serverUrl: _normalizeServerUrl(serverOrigin),
      );
    }
  }

  final shortCode = _normalizeShortCode(raw);
  if (shortCode != null) {
    return ParsedSecureScan(scanShortCode: shortCode);
  }

  final payload = _normalizePayload(raw);
  if (payload == null) {
    return null;
  }
  return ParsedSecureScan(scanPayload: payload);
}

String? _normalizePayload(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

String? _normalizeShortCode(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final normalized =
      trimmed.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  if (normalized.length != 8) {
    return null;
  }
  return normalized;
}

String? _normalizeServerUrl(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final parsed = Uri.tryParse(trimmed);
  if (parsed == null || (parsed.scheme != 'http' && parsed.scheme != 'https')) {
    return null;
  }
  return parsed.toString().replaceAll(RegExp(r'/$'), '');
}
