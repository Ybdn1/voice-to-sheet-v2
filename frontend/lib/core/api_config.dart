import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

class ApiConfig {
  /// IP locale du PC sur le reseau Wi-Fi.
  /// A mettre a jour si l'IP change (ou utiliser la variable d'env VOICE_TO_SHEET_API_URL).
  static const String _pcLanIp = '172.20.10.9';

  static String get defaultBaseUrl {
    const customUrl = String.fromEnvironment('VOICE_TO_SHEET_API_URL');
    if (customUrl.isNotEmpty) {
      return customUrl;
    }

    if (kIsWeb) {
      return 'http://127.0.0.1:8000';
    }

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return 'http://$_pcLanIp:8000';
    }

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
