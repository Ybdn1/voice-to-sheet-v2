import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;

import '../models/auth_models.dart';
import '../models/reference_models.dart';
import '../models/report_models.dart';

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VoiceToSheetApi {
  VoiceToSheetApi({required this.baseUrl});

  final String baseUrl;
  static const Duration _timeout = Duration(seconds: 12);

  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: _jsonHeaders(),
      body: jsonEncode(
        <String, dynamic>{
          'username': username,
          'password': password,
        },
      ),
    ).timeout(_timeout);

    final payload = _decodeResponse(response);
    return AuthSession.fromJson(payload as Map<String, dynamic>);
  }

  Future<List<ReferenceItem>> fetchSites(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/references/sites'),
      headers: _authorizedHeaders(token),
    ).timeout(_timeout);

    final payload = _decodeResponse(response) as List<dynamic>;
    return payload
        .map((item) => ReferenceItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<ReferenceItem>> fetchContracts(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/references/contracts'),
      headers: _authorizedHeaders(token),
    ).timeout(_timeout);

    final payload = _decodeResponse(response) as List<dynamic>;
    return payload
        .map((item) => ReferenceItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<ZoneItem>> fetchZones(
    String token, {
    required String siteId,
    required String contractId,
  }) async {
    final uri = Uri.parse('$baseUrl/references/zones').replace(
      queryParameters: <String, String>{
        'site_id': siteId,
        'contract_id': contractId,
      },
    );

    final response = await http.get(
      uri,
      headers: _authorizedHeaders(token),
    ).timeout(_timeout);

    final payload = _decodeResponse(response) as List<dynamic>;
    return payload
        .map((item) => ZoneItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<InterpretResponse> interpret(
    String token,
    InterpretRequest request,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/reports/interpret'),
      headers: _authorizedHeaders(token),
      body: jsonEncode(request.toJson()),
    ).timeout(_timeout);

    final payload = _decodeResponse(response);
    return InterpretResponse.fromJson(payload as Map<String, dynamic>);
  }

  Map<String, String> _jsonHeaders() {
    return <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  Map<String, String> _authorizedHeaders(String token) {
    return <String, String>{
      ..._jsonHeaders(),
      'Authorization': 'Bearer $token',
    };
  }

  dynamic _decodeResponse(http.Response response) {
    final decodedBody = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decodedBody;
    }

    final message = _extractErrorMessage(decodedBody);
    throw ApiException(message);
  }

  String _extractErrorMessage(dynamic body) {
    if (body is Map<String, dynamic>) {
      final detail = body['detail'];

      if (detail is String && detail.isNotEmpty) {
        return detail;
      }

      if (detail is Map<String, dynamic>) {
        final message = detail['message'];
        final error = detail['error'];
        if (message is String && error is String) {
          return '$message\n$error';
        }
        if (message is String) {
          return message;
        }
      }
    }

    return 'Une erreur reseau est survenue.';
  }
}
