import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

class ApiConfig {
  /// IP locale du PC sur le réseau Wi-Fi.
  /// À mettre à jour si l'IP change (ou utiliser la variable d'env VOICE_TO_SHEET_API_URL).
  static const String _pcLanIp = '10.250.136.170';

  static String get baseUrl {
    const customUrl = String.fromEnvironment('VOICE_TO_SHEET_API_URL');
    if (customUrl.isNotEmpty) {
      return customUrl;
    }

    if (kIsWeb) {
      return 'http://127.0.0.1:8000';
    }

    // Sur Android/iOS/TV : utiliser l'IP LAN du PC pour joindre le backend
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return 'http://$_pcLanIp:8000';
    }

    // Sur PC (Windows/Linux/macOS) : localhost suffit
    return 'http://localhost:8000';
  }
}
