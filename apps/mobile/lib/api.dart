import 'dart:convert';

import 'package:http/http.dart' as http;

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
}
