import 'package:flutter/material.dart';

import '../core/api_config.dart';
import '../models/auth_models.dart';
import '../services/voice_to_sheet_api.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.api,
    required this.currentBaseUrl,
    required this.defaultBaseUrl,
    required this.onBaseUrlChanged,
    required this.onLoggedIn,
  });

  final VoiceToSheetApi api;
  final String currentBaseUrl;
  final String defaultBaseUrl;
  final Future<void> Function(String baseUrl) onBaseUrlChanged;
  final ValueChanged<AuthSession> onLoggedIn;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _baseUrlController;
  final _usernameController = TextEditingController(text: 'agent.demo');
  final _passwordController = TextEditingController(text: 'demo1234');

  bool _isSavingBaseUrl = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: widget.currentBaseUrl);
  }

  @override
  void didUpdateWidget(covariant LoginPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentBaseUrl != widget.currentBaseUrl &&
        _baseUrlController.text.trim() != widget.currentBaseUrl) {
      _baseUrlController.text = widget.currentBaseUrl;
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _applyBaseUrl(String rawValue) async {
    final normalizedValue = ApiConfig.normalizeBaseUrl(rawValue);
    if (normalizedValue == null) {
      setState(() {
        _errorMessage =
            'Entre une URL backend valide, par exemple http://10.250.136.170:8000';
      });
      return;
    }

    setState(() {
      _isSavingBaseUrl = true;
      _errorMessage = null;
    });

    try {
      await widget.onBaseUrlChanged(normalizedValue);

      if (!mounted) {
        return;
      }

      _baseUrlController.text = normalizedValue;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backend configure: $normalizedValue'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Impossible de sauvegarder le backend.\nDetail: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSavingBaseUrl = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final normalizedBaseUrl = ApiConfig.normalizeBaseUrl(_baseUrlController.text);
    if (normalizedBaseUrl == null) {
      setState(() {
        _errorMessage =
            'Entre une URL backend valide, par exemple http://10.250.136.170:8000';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      if (normalizedBaseUrl != widget.api.baseUrl) {
        await widget.onBaseUrlChanged(normalizedBaseUrl);
      }

      if (!mounted) {
        return;
      }

      _baseUrlController.text = normalizedBaseUrl;
      final api = VoiceToSheetApi(baseUrl: normalizedBaseUrl);
      final session = await api.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (!mounted) {
        return;
      }

      widget.onLoggedIn(session);
    } on ApiException catch (error) {
      setState(() {
        _errorMessage = error.message;
      });
    } catch (error) {
      setState(() {
        _errorMessage =
            'Connexion impossible ($normalizedBaseUrl).\n'
            'Verifie que le backend tourne, que le telephone est sur le meme Wi-Fi que le PC, puis reessaie.\n'
            'Detail: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFFEAF6F2),
              Color(0xFFF8F4EA),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.mic_external_on_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'VoiceToSheet',
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF183531),
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Connexion agent pour relever les equipements, anomalies et controles terrain.',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: const Color(0xFF526965),
                                ),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _baseUrlController,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: 'URL backend',
                              hintText: 'http://10.250.136.170:8000',
                              prefixIcon: Icon(Icons.cloud_outlined),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Entre une URL backend.';
                              }
                              if (ApiConfig.normalizeBaseUrl(value) == null) {
                                return 'Entre une URL http:// ou https:// valide.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isSavingBaseUrl || _isSubmitting
                                      ? null
                                      : () => _applyBaseUrl(_baseUrlController.text),
                                  icon: _isSavingBaseUrl
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.settings_ethernet_rounded),
                                  label: const Text('Appliquer'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              TextButton(
                                onPressed: _isSavingBaseUrl || _isSubmitting
                                    ? null
                                    : () {
                                        _baseUrlController.text = widget.defaultBaseUrl;
                                      },
                                child: const Text('URL par defaut'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Pour un test sur telephone: mets l IP du PC, puis garde le mobile sur le meme Wi-Fi.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF526965),
                                ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Identifiant',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Entre un identifiant.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Mot de passe',
                              prefixIcon: Icon(Icons.lock_outline_rounded),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Entre un mot de passe.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          if (_errorMessage != null) ...<Widget>[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF1F1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFFFD5D5)),
                              ),
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Color(0xFF8B2D2D)),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          FilledButton.icon(
                            onPressed: _isSubmitting ? null : _submit,
                            icon: _isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.login_rounded),
                            label: Text(_isSubmitting ? 'Connexion...' : 'Se connecter'),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: () {
                              _usernameController.text = 'agent.demo';
                              _passwordController.text = 'demo1234';
                            },
                            child: const Text('Utiliser le compte de demo'),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Backend actuel: ${widget.api.baseUrl}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF526965),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
