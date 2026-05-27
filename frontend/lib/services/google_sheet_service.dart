import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../core/google_sheet_config.dart';
import '../models/report_models.dart';

class CreatedGoogleSheet {
  CreatedGoogleSheet({
    required this.spreadsheetId,
    required this.title,
    required this.url,
  });

  final String spreadsheetId;
  final String title;
  final String url;
}

class GoogleSheetService {
  GoogleSheetService({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  static const List<String> _scopes = <String>[
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/spreadsheets',
  ];

  final GoogleSignIn _googleSignIn;
  bool _isInitialized = false;
  GoogleSignInAccount? _authenticatedUser;

  Future<CreatedGoogleSheet> createSheet(List<EquipmentRow> rows) async {
    if (rows.isEmpty) {
      throw StateError('Aucune ligne a exporter.');
    }

    if (kIsWeb) {
      throw UnsupportedError(
        'La creation de Google Sheet est prevue pour Android dans cette version.',
      );
    }

    await _ensureInitialized();

    final user = await _authenticateUser();
    final authorization = await _authorizeUser(user);
    final client = authorization.authClient(scopes: _scopes);

    try {
      final title = _buildSheetTitle(rows.first);
      final spreadsheet = await _createSpreadsheet(client, title);
      await _appendRows(client, spreadsheetId: spreadsheet.spreadsheetId, rows: rows);

      return spreadsheet;
    } finally {
      client.close();
    }
  }

  Future<void> _ensureInitialized() async {
    if (_isInitialized) {
      return;
    }

    await _googleSignIn.initialize(
      clientId: GoogleSheetConfig.clientId.trim().isEmpty
          ? null
          : GoogleSheetConfig.clientId.trim(),
      serverClientId: GoogleSheetConfig.serverClientId.trim().isEmpty
          ? null
          : GoogleSheetConfig.serverClientId.trim(),
    );

    _isInitialized = true;
  }

  Future<GoogleSignInAccount> _authenticateUser() async {
    if (!_googleSignIn.supportsAuthenticate()) {
      throw UnsupportedError(
        'La connexion Google interactive n est pas disponible sur cette plateforme.',
      );
    }

    if (_authenticatedUser != null) {
      return _authenticatedUser!;
    }

    final lightweightAuthentication =
        _googleSignIn.attemptLightweightAuthentication();
    final restoredUser = lightweightAuthentication == null
        ? null
        : await lightweightAuthentication;
    if (restoredUser != null) {
      _authenticatedUser = restoredUser;
      return restoredUser;
    }

    if (!GoogleSheetConfig.hasAnyClientConfig) {
      throw StateError(GoogleSheetConfig.missingConfigMessage);
    }

    final user = await _googleSignIn.authenticate(scopeHint: _scopes);
    _authenticatedUser = user;
    return user;
  }

  Future<GoogleSignInClientAuthorization> _authorizeUser(
    GoogleSignInAccount user,
  ) async {
    final existingAuthorization =
        await user.authorizationClient.authorizationForScopes(_scopes);
    if (existingAuthorization != null) {
      return existingAuthorization;
    }

    return user.authorizationClient.authorizeScopes(_scopes);
  }

  Future<CreatedGoogleSheet> _createSpreadsheet(
    http.Client client,
    String title,
  ) async {
    final response = await client.post(
      Uri.parse('https://sheets.googleapis.com/v4/spreadsheets'),
      headers: _jsonHeaders,
      body: jsonEncode(
        <String, Object?>{
          'properties': <String, String>{'title': title},
          'sheets': <Map<String, Object?>>[
            <String, Object?>{
              'properties': <String, String>{'title': 'Releve'},
            },
          ],
        },
      ),
    );

    final payload = _decodeJson(response);
    final spreadsheetId = payload['spreadsheetId'] as String?;
    final spreadsheetUrl = payload['spreadsheetUrl'] as String?;

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_extractGoogleError(payload));
    }

    if (spreadsheetId == null || spreadsheetUrl == null) {
      throw StateError('Google Sheets n a pas retourne l identifiant attendu.');
    }

    return CreatedGoogleSheet(
      spreadsheetId: spreadsheetId,
      title: title,
      url: spreadsheetUrl,
    );
  }

  Future<void> _appendRows(
    http.Client client, {
    required String spreadsheetId,
    required List<EquipmentRow> rows,
  }) async {
    final values = <List<String>>[
      <String>['Site', 'Contrat', 'Zone', 'Equipement', 'Description'],
      ...rows.map(
        (row) => <String>[
          row.site,
          row.contrat,
          row.zone,
          row.equipement,
          row.description,
        ],
      ),
    ];

    final response = await client.put(
      Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/'
        '$spreadsheetId/values/${Uri.encodeComponent('Releve!A1')}'
        '?valueInputOption=RAW',
      ),
      headers: _jsonHeaders,
      body: jsonEncode(
        <String, Object?>{
          'range': 'Releve!A1',
          'majorDimension': 'ROWS',
          'values': values,
        },
      ),
    );

    final payload = _decodeJson(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_extractGoogleError(payload));
    }
  }

  String _buildSheetTitle(EquipmentRow firstRow) {
    final timestamp = DateTime.now().toIso8601String().substring(0, 16);
    return 'VoiceToSheet - ${firstRow.site} - ${firstRow.zone} - $timestamp';
  }

  Map<String, String> get _jsonHeaders {
    return const <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  Map<String, dynamic> _decodeJson(http.Response response) {
    if (response.body.isEmpty) {
      return <String, dynamic>{};
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    return <String, dynamic>{};
  }

  String _extractGoogleError(Map<String, dynamic> payload) {
    final error = payload['error'];
    if (error is Map<String, dynamic>) {
      final message = error['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
    }

    return 'Impossible de creer la Google Sheet.';
  }
}
