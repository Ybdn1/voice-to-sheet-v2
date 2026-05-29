import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/auth_models.dart';
import '../models/reference_models.dart';
import '../models/report_models.dart';
import '../services/voice_to_sheet_api.dart';
import 'report_result_page.dart';

final List<ReferenceItem> _fallbackSites = <ReferenceItem>[
  ReferenceItem(id: 'la-valette', name: 'La Valette'),
  ReferenceItem(id: 'bastide', name: 'La Bastide'),
];

final List<ReferenceItem> _fallbackContracts = <ReferenceItem>[
  ReferenceItem(id: 'exploitation', name: 'Exploitation'),
  ReferenceItem(id: 'maintenance', name: 'Maintenance'),
];

final List<ZoneItem> _fallbackZones = <ZoneItem>[
  ZoneItem(
    id: 'boue-la-valette-exploitation',
    siteId: 'la-valette',
    contractId: 'exploitation',
    name: 'Boue',
  ),
  ZoneItem(
    id: 'entree-la-valette-exploitation',
    siteId: 'la-valette',
    contractId: 'exploitation',
    name: 'Entree des eaux',
  ),
  ZoneItem(
    id: 'eaux-traitees-la-valette-maintenance',
    siteId: 'la-valette',
    contractId: 'maintenance',
    name: 'Eaux traitees',
  ),
  ZoneItem(
    id: 'bassin-bastide-maintenance',
    siteId: 'bastide',
    contractId: 'maintenance',
    name: 'Bassin principal',
  ),
];

class ReportFormPage extends StatefulWidget {
  const ReportFormPage({
    super.key,
    required this.api,
    required this.session,
    required this.onLogout,
  });

  final VoiceToSheetApi api;
  final AuthSession session;
  final VoidCallback onLogout;

  @override
  State<ReportFormPage> createState() => _ReportFormPageState();
}

class _ReportFormPageState extends State<ReportFormPage> {
  final _descriptionController = TextEditingController();
  final SpeechToText _speech = SpeechToText();

  List<ReferenceItem> _sites = <ReferenceItem>[];
  List<ReferenceItem> _contracts = <ReferenceItem>[];
  List<ZoneItem> _zones = <ZoneItem>[];

  String? _selectedSiteId;
  String? _selectedContractId;
  String? _selectedZoneId;

  static const Duration _silenceTimeout = Duration(minutes: 5);

  bool _isSyncingReferences = false;
  bool _isLoadingZones = false;
  bool _isSubmitting = false;
  bool _speechReady = false;
  bool _isListening = false;
  bool _userWantsToListen = false;
  String _committedText = '';
  DateTime? _lastSpeechTime;
  String? _errorMessage;

  /// Identifiant de session micro : incremente a chaque nouveau listen().
  /// Les callbacks onResult de la session precedente sont ignores.
  int _listenSession = 0;

  ReferenceItem? get _selectedSite {
    for (final item in _sites) {
      if (item.id == _selectedSiteId) return item;
    }
    return null;
  }

  ReferenceItem? get _selectedContract {
    for (final item in _contracts) {
      if (item.id == _selectedContractId) return item;
    }
    return null;
  }

  ZoneItem? get _selectedZone {
    for (final item in _zones) {
      if (item.id == _selectedZoneId) return item;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _applyFallbackReferences();
    unawaited(_loadReferences());
    if (!kIsWeb) {
      unawaited(_initSpeech());
    }
  }

  @override
  void dispose() {
    _userWantsToListen = false;
    _descriptionController.dispose();
    _speech.stop();
    super.dispose();
  }

  List<ZoneItem> _buildFallbackZones({
    required String? siteId,
    required String? contractId,
  }) {
    return _fallbackZones.where((zone) {
      return zone.siteId == siteId && zone.contractId == contractId;
    }).toList();
  }

  void _applyFallbackReferences() {
    _sites = List<ReferenceItem>.from(_fallbackSites);
    _contracts = List<ReferenceItem>.from(_fallbackContracts);
    _selectedSiteId ??= _sites.isNotEmpty ? _sites.first.id : null;
    _selectedContractId ??= _contracts.isNotEmpty ? _contracts.first.id : null;
    _zones = _buildFallbackZones(
      siteId: _selectedSiteId,
      contractId: _selectedContractId,
    );
    _selectedZoneId = _zones.isNotEmpty ? _zones.first.id : null;
  }

  Future<void> _loadReferences() async {
    setState(() {
      _isSyncingReferences = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        widget.api.fetchSites(widget.session.accessToken),
        widget.api.fetchContracts(widget.session.accessToken),
      ]);

      if (!mounted) return;

      setState(() {
        _sites = results[0] as List<ReferenceItem>;
        _contracts = results[1] as List<ReferenceItem>;
        _selectedSiteId = _sites.any((s) => s.id == _selectedSiteId)
            ? _selectedSiteId
            : (_sites.isNotEmpty ? _sites.first.id : null);
        _selectedContractId = _contracts.any((c) => c.id == _selectedContractId)
            ? _selectedContractId
            : (_contracts.isNotEmpty ? _contracts.first.id : null);
      });

      await _loadZones();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'References indisponibles — mode local actif.\n${error.message}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Impossible de synchroniser les references — mode local actif.';
      });
    } finally {
      if (mounted) setState(() { _isSyncingReferences = false; });
    }
  }

  Future<void> _loadZones() async {
    final siteId = _selectedSiteId;
    final contractId = _selectedContractId;

    if (siteId == null || contractId == null) {
      setState(() {
        _zones = <ZoneItem>[];
        _selectedZoneId = null;
      });
      return;
    }

    setState(() {
      _isLoadingZones = true;
      _zones = _buildFallbackZones(siteId: siteId, contractId: contractId);
      _selectedZoneId = _zones.isNotEmpty ? _zones.first.id : null;
    });

    try {
      final zones = await widget.api.fetchZones(
        widget.session.accessToken,
        siteId: siteId,
        contractId: contractId,
      );

      if (!mounted) return;

      setState(() {
        _zones = zones;
        _selectedZoneId = zones.isNotEmpty ? zones.first.id : null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Zones indisponibles — mode local actif.\n${error.message}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Impossible de synchroniser les zones — mode local actif.';
      });
    } finally {
      if (mounted) setState(() { _isLoadingZones = false; });
    }
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          if (_userWantsToListen) {
            final lastSpeech = _lastSpeechTime;
            final silenceTooLong = lastSpeech != null &&
                DateTime.now().difference(lastSpeech) >= _silenceTimeout;

            if (silenceTooLong) {
              _userWantsToListen = false;
              _committedText = '';
              _lastSpeechTime = null;
              setState(() { _isListening = false; });
            } else {
              // Android a coupe la session → on valide le texte actuel et on relance.
              _committedText = _descriptionController.text.trim();
              unawaited(_startListening());
            }
          } else {
            setState(() { _isListening = false; });
          }
        }
      },
      onError: (error) {
        if (!mounted) return;
        if (_userWantsToListen) {
          _committedText = _descriptionController.text.trim();
          Future<void>.delayed(const Duration(milliseconds: 500), () {
            if (_userWantsToListen && mounted) unawaited(_startListening());
          });
        } else {
          setState(() { _isListening = false; });
        }
      },
    );

    if (mounted) setState(() { _speechReady = available; });
  }

  Future<void> _startListening() async {
    if (!mounted) return;

    // Nouvel identifiant de session : les callbacks de l'ancienne session
    // seront ignores, ce qui evite la duplication du texte.
    _listenSession++;
    final mySession = _listenSession;

    await _speech.listen(
      localeId: 'fr_FR',
      listenFor: const Duration(minutes: 2),
      pauseFor: const Duration(seconds: 20),
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
      ),
      onResult: (result) {
        // Ignorer les callbacks d'une session perimee.
        if (mySession != _listenSession) return;

        final newWords = result.recognizedWords.trim();
        if (newWords.isNotEmpty) {
          _lastSpeechTime = DateTime.now();
        }
        final fullText = _committedText.isEmpty
            ? newWords
            : '$_committedText $newWords';
        _descriptionController.text = fullText;
        _descriptionController.selection = TextSelection.fromPosition(
          TextPosition(offset: _descriptionController.text.length),
        );
        if (mounted) setState(() {});
      },
    );

    if (mounted) setState(() { _isListening = true; });
  }

  Future<void> _toggleListening() async {
    if (!_speechReady) await _initSpeech();

    if (!_speechReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dictee non disponible sur cet appareil.')),
      );
      return;
    }

    if (_isListening || _userWantsToListen) {
      _userWantsToListen = false;
      _committedText = '';
      _lastSpeechTime = null;
      await _speech.stop();
      if (mounted) setState(() { _isListening = false; });
      return;
    }

    _userWantsToListen = true;
    _committedText = _descriptionController.text.trim();
    _lastSpeechTime = DateTime.now();
    await _startListening();
  }

  Future<void> _submit() async {
    final site = _selectedSite;
    final contract = _selectedContract;
    final zone = _selectedZone;
    final description = _descriptionController.text.trim();

    if (site == null || contract == null || zone == null) {
      setState(() { _errorMessage = 'Choisis le site, le contrat et la zone.'; });
      return;
    }
    if (description.isEmpty) {
      setState(() { _errorMessage = 'Ajoute une description ou utilise le micro.'; });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.api.interpret(
        widget.session.accessToken,
        InterpretRequest(
          site: site.name,
          contrat: contract.name,
          zone: zone.name,
          description: description,
        ),
      );

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReportResultPage(
            initialRows: result.rows,
            rawModelOutput: result.rawModelOutput,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() { _errorMessage = error.message; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _errorMessage = 'Extraction impossible. Verifie le backend puis reessaie.'; });
    } finally {
      if (mounted) setState(() { _isSubmitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Nouveau releve', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(widget.session.fullName, style: theme.textTheme.bodySmall),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Se deconnecter',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            // ─── Site ────────────────────────────────────────────────────────
            _DropdownCard(
              label: 'Site',
              icon: Icons.location_on_outlined,
              isLoading: _isSyncingReferences,
              value: _selectedSiteId,
              items: _sites.map((s) => _DropdownEntry(id: s.id, name: s.name)).toList(),
              onChanged: (value) async {
                setState(() => _selectedSiteId = value);
                await _loadZones();
              },
            ),
            const SizedBox(height: 12),
            // ─── Contrat ─────────────────────────────────────────────────────
            _DropdownCard(
              label: 'Contrat',
              icon: Icons.description_outlined,
              isLoading: _isSyncingReferences,
              value: _selectedContractId,
              items: _contracts.map((c) => _DropdownEntry(id: c.id, name: c.name)).toList(),
              onChanged: (value) async {
                setState(() => _selectedContractId = value);
                await _loadZones();
              },
            ),
            const SizedBox(height: 12),
            // ─── Zone ─────────────────────────────────────────────────────────
            _DropdownCard(
              label: 'Zone',
              icon: Icons.map_outlined,
              isLoading: _isLoadingZones,
              value: _selectedZoneId,
              items: _zones.map((z) => _DropdownEntry(id: z.id, name: z.name)).toList(),
              onChanged: (value) => setState(() => _selectedZoneId = value),
            ),
            const SizedBox(height: 20),
            // ─── Description + Micro ─────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF0F766E)),
                        const SizedBox(width: 8),
                        const Text(
                          'Description',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Color(0xFF132A27),
                          ),
                        ),
                        const Spacer(),
                        if (!kIsWeb)
                          FilledButton.tonalIcon(
                            onPressed: _toggleListening,
                            style: FilledButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              backgroundColor: _isListening
                                  ? const Color(0xFFDCFCE7)
                                  : theme.colorScheme.surfaceContainerHighest,
                              foregroundColor: _isListening
                                  ? const Color(0xFF15803D)
                                  : theme.colorScheme.onSurface,
                            ),
                            icon: Icon(
                              _isListening
                                  ? Icons.stop_circle_outlined
                                  : Icons.mic_none_rounded,
                              size: 18,
                            ),
                            label: Text(
                              _isListening ? 'Stop' : 'Dicter',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                    if (_isListening) ...<Widget>[
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Enregistrement en cours...',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF0F766E),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descriptionController,
                      minLines: 5,
                      maxLines: 12,
                      decoration: InputDecoration(
                        hintText: kIsWeb
                            ? 'Saisir le releve ici...'
                            : 'Appuie sur "Dicter" ou saisir ici...\n'
                              'Ex: reservoir eaux brutes, 3 pompes, pompe 1 en panne...',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // ─── Actions ─────────────────────────────────────────────────────
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _descriptionController.clear();
                      _committedText = '';
                      setState(() {});
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Effacer'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(_isSubmitting ? 'Extraction...' : 'Valider'),
                  ),
                ),
              ],
            ),
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFD5D5)),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Color(0xFF8B2D2D)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Helpers ────────────────────────────────────────────────────────────────

class _DropdownEntry {
  const _DropdownEntry({required this.id, required this.name});
  final String id;
  final String name;
}

class _DropdownCard extends StatelessWidget {
  const _DropdownCard({
    required this.label,
    required this.icon,
    required this.isLoading,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final bool isLoading;
  final String? value;
  final List<_DropdownEntry> items;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    // Si la valeur n'est pas dans la liste (ex: chargement en cours), on met null.
    final safeValue = items.any((e) => e.id == value) ? value : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 16, color: const Color(0xFF0F766E)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Color(0xFF526965),
                  ),
                ),
                if (isLoading) ...<Widget>[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: safeValue,
              isExpanded: true,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              hint: Text(isLoading ? 'Chargement...' : 'Selectionner $label'),
              items: items
                  .map(
                    (e) => DropdownMenuItem<String>(
                      value: e.id,
                      child: Text(e.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: items.isEmpty ? null : onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
