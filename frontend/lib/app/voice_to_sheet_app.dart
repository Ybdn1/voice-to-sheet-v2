import 'package:flutter/material.dart';

import '../core/api_config.dart';
import '../core/backend_url_store.dart';
import '../models/auth_models.dart';
import '../screens/login_page.dart';
import '../screens/report_form_page.dart';
import '../services/voice_to_sheet_api.dart';

class VoiceToSheetApp extends StatefulWidget {
  const VoiceToSheetApp({super.key});

  @override
  State<VoiceToSheetApp> createState() => _VoiceToSheetAppState();
}

class _VoiceToSheetAppState extends State<VoiceToSheetApp> {
  final BackendUrlStore _backendUrlStore = BackendUrlStore();
  AuthSession? _session;
  String? _baseUrl;
  bool _isLoadingConfig = true;

  @override
  void initState() {
    super.initState();
    _loadBaseUrl();
  }

  Future<void> _loadBaseUrl() async {
    final baseUrl = await _backendUrlStore.loadBaseUrl();
    if (!mounted) {
      return;
    }

    setState(() {
      _baseUrl = baseUrl;
      _isLoadingConfig = false;
    });
  }

  Future<void> _updateBaseUrl(String baseUrl) async {
    await _backendUrlStore.saveBaseUrl(baseUrl);
    if (!mounted) {
      return;
    }

    setState(() {
      _baseUrl = baseUrl;
      _session = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingConfig || _baseUrl == null) {
      return MaterialApp(
        title: 'VoiceToSheet',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final api = VoiceToSheetApi(baseUrl: _baseUrl!);

    return MaterialApp(
      title: 'VoiceToSheet',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: _session == null
          ? LoginPage(
              api: api,
              currentBaseUrl: _baseUrl!,
              defaultBaseUrl: ApiConfig.defaultBaseUrl,
              onBaseUrlChanged: _updateBaseUrl,
              onLoggedIn: (session) {
                setState(() {
                  _session = session;
                });
              },
            )
          : ReportFormPage(
              api: api,
              session: _session!,
              onLogout: () {
                setState(() {
                  _session = null;
                });
              },
            ),
    );
  }

  ThemeData _buildTheme() {
    const base = Color(0xFF0F766E);
    final scheme = ColorScheme.fromSeed(
      seedColor: base,
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xFF0F766E),
      secondary: const Color(0xFFD97706),
      surface: Colors.white,
      onSurface: const Color(0xFF132A27),
      surfaceContainerHighest: const Color(0xFFE8F4F1),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF3F7F5),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFD3E5DF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFD3E5DF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFE0ECE8)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Color(0xFF14312D),
        elevation: 0,
        centerTitle: false,
      ),
    );
  }
}
