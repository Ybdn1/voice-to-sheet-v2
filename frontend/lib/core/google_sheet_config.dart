class GoogleSheetConfig {
  const GoogleSheetConfig._();

  static const String clientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
  static const String serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  static bool get hasAnyClientConfig =>
      clientId.trim().isNotEmpty || serverClientId.trim().isNotEmpty;

  static String get missingConfigMessage {
    return 'Configuration Google manquante. Ajoute GOOGLE_SERVER_CLIENT_ID '
        'au lancement Flutter pour Android, ou configure google-services.json.';
  }
}
