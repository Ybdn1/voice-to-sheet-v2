import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;

import '../models/auth_models.dart';
import '../models/reference_models.dart';
import '../models/report_models.dart';

// ── Exceptions ────────────────────────────────────────────────────────────────

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Lancée sur toute réponse HTTP 401 — session expirée ou token invalide.
class AuthExpiredException implements Exception {
  const AuthExpiredException();
  @override
  String toString() => 'Session expirée. Veuillez vous reconnecter.';
}

// ── API client ────────────────────────────────────────────────────────────────

class VoiceToSheetApi {
  VoiceToSheetApi({required this.baseUrl});

  final String baseUrl;

  static const Duration _shortTimeout = Duration(seconds: 12);

  /// Timeout étendu pour l'appel Mistral (extraction IA peut prendre 20-40 s).
  static const Duration _interpretTimeout = Duration(seconds: 60);

  // ── Méthodes publiques ────────────────────────────────────────────────────

  /// Ping /health — utilisé pour détecter si le backend Render est endormi.
  Future<void> ping() async {
    await http
        .get(
          Uri.parse('$baseUrl/health'),
          headers: _jsonHeaders(),
        )
        .timeout(_shortTimeout);
  }

  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/login'),
          headers: _jsonHeaders(),
          body: jsonEncode(<String, dynamic>{
            'username': username,
            'password': password,
          }),
        )
        .timeout(_shortTimeout);

    final payload = _decodeResponse(response);
    return AuthSession.fromJson(payload as Map<String, dynamic>);
  }

  Future<List<ReferenceItem>> fetchSites(String token) async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/references/sites'),
          headers: _authorizedHeaders(token),
        )
        .timeout(_shortTimeout);

    final payload = _decodeResponse(response) as List<dynamic>;
    return payload
        .map((item) => ReferenceItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<ReferenceItem>> fetchContracts(String token) async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/references/contracts'),
          headers: _authorizedHeaders(token),
        )
        .timeout(_shortTimeout);

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
    final response = await http
        .get(uri, headers: _authorizedHeaders(token))
        .timeout(_shortTimeout);

    final payload = _decodeResponse(response) as List<dynamic>;
    return payload
        .map((item) => ZoneItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<InterpretResponse> interpret(
    String token,
    InterpretRequest request,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/reports/interpret'),
          headers: _authorizedHeaders(token),
          body: jsonEncode(request.toJson()),
        )
        .timeout(_interpretTimeout);

    final payload = _decodeResponse(response);
    return InterpretResponse.fromJson(payload as Map<String, dynamic>);
  }

  // ── Helpers privés ────────────────────────────────────────────────────────

  Map<String, String> _jsonHeaders() => <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Map<String, String> _authorizedHeaders(String token) => <String, String>{
        ..._jsonHeaders(),
        'Authorization': 'Bearer $token',
      };

  dynamic _decodeResponse(http.Response response) {
    // 401 → session expirée : exception dédiée pour rediriger vers login.
    if (response.statusCode == 401) {
      throw const AuthExpiredException();
    }

    final decodedBody = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decodedBody;
    }

    throw ApiException(_extractErrorMessage(decodedBody));
  }

  String _extractErrorMessage(dynamic body) {
    if (body is Map<String, dynamic>) {
      final detail = body['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      if (detail is Map<String, dynamic>) {
        final message = detail['message'];
        final error = detail['error'];
        if (message is String && error is String) return '$message\n$error';
        if (message is String) return message;
      }
    }
    return 'Une erreur reseau est survenue.';
  }
}
