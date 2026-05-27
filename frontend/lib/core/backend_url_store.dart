import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

class BackendUrlStore {
  static const String _key = 'voice_to_sheet_backend_url';

  Future<String> loadBaseUrl() async {
    final preferences = await SharedPreferences.getInstance();
    final savedValue = preferences.getString(_key);
    final normalizedValue = savedValue == null
        ? null
        : ApiConfig.normalizeBaseUrl(savedValue);

    return normalizedValue ?? ApiConfig.defaultBaseUrl;
  }

  Future<void> saveBaseUrl(String baseUrl) async {
    final normalizedValue = ApiConfig.normalizeBaseUrl(baseUrl);
    if (normalizedValue == null) {
      throw ArgumentError('URL backend invalide.');
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, normalizedValue);
  }
}
