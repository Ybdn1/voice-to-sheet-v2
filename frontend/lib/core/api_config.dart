import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

class ApiConfig {
  /// URL du backend heberge sur Render (production).
  static const String _prodUrl = 'https://voice-to-sheet-v2.onrender.com';

  /// IP locale du PC — utilisee uniquement si VOICE_TO_SHEET_API_URL est defini
  /// (developpement local uniquement).
  static const String _pcLanIp = '172.20.10.9';

  static String get defaultBaseUrl {
    const customUrl = String.fromEnvironment('VOICE_TO_SHEET_API_URL');
    if (customUrl.isNotEmpty) {
      return customUrl;
    }

    // En production (mobile ou web) : on utilise toujours l'URL Render.
    if (kIsWeb || (!kIsWeb && (Platform.isAndroid || Platform.isIOS))) {
      return _prodUrl;
    }

    // Desktop local (dev) : localhost
    return 'http://localhost:8000';
  }

  static String get baseUrl => defaultBaseUrl;

  static String? normalizeBaseUrl(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final sanitized = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    final uri = Uri.tryParse(sanitized);

    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return null;
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return null;
    }

    return sanitized;
  }
}
