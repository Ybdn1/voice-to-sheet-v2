import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/auth_models.dart';
import '../models/reference_models.dart';
import '../models/report_models.dart';
import '../screens/history_page.dart';
import '../services/draft_service.dart';
import '../services/voice_to_sheet_api.dart';
import 'report_result_page.dart';

// ── Données de fallback ───────────────────────────────────────────────────────

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

// ── Templates de phrases rapides ──────────────────────────────────────────────

const List<String> _phraseTemplates = <String>[
  'Pompe en panne',
  'Fuite detectee',
  'Vanne bloquee',
  'Niveau bas',
  'Niveau haut',
  'Controle normal',
  'Remplacement necessaire',
  'Entretien preventif realise',
  'Anomalie constatee',
  'Mesure relevee : ',
  'Bruit anormal',
  'Vibration excessive',
];

// ── Widget principal ──────────────────────────────────────────────────────────

class ReportFormPage extends StatefulWidget {
  const ReportFormPage({
    super.key,
    required this.api,
    required this.session,
    required this.onLogout,
    required this.onSessionExpired,
  });

  final VoiceToSheetApi api;
  final AuthSession session;
  final VoidCallback onLogout;

  /// Appelé quand le backend répond 401 — redirige vers login avec message.
  final VoidCallback onSessionExpired;

  @override
  State<ReportFormPage> createState() => _ReportFormPageState();
}

class _ReportFormPageState extends State<ReportFormPage> {
  // ── Contrôleurs ───────────────────────────────────────────────────────────
  final _descriptionController = TextEditingController();
  final SpeechToText _speech = SpeechToText();
  final DraftService _draftService = DraftService();

  // ── Références ────────────────────────────────────────────────────────────
  List<ReferenceItem> _sites = <ReferenceItem>[];
  List<ReferenceItem> _contracts = <ReferenceItem>[];
  List<ZoneItem> _zones = <ZoneItem>[];

  String? _selectedSiteId;
  String? _selectedContractId;
  String? _selectedZoneId;

  // ── États UI ──────────────────────────────────────────────────────────────
  bool _isSyncingReferences = false;
  bool _isLoadingZones = false;
  bool _isSubmitting = false;
  bool _speechReady = false;
  bool _isListening = false;
  bool _userWantsToListen = false;
  bool _isOffline = false;
  bool _hasDraftRestored = false;
  String? _errorMessage;

  // ── Dictée ────────────────────────────────────────────────────────────────
  static const Duration _silenceTimeout = Duration(minutes: 5);
  String _committedText = '';
  DateTime? _lastSpeechTime;
  int _listenSession = 0;

  // ── Draft (auto-save) ─────────────────────────────────────────────────────
  Timer? _draftSaveTimer;

  // ── Connectivité ─────────────────────────────────────────────────────────
  late StreamSubscription<List<ConnectivityResult>> _connectivitySub;

  // ── Sélections calculées ─────────────────────────────────────────────────
  ReferenceItem? get _selectedSite =>
      _sites.firstWhereOrNull((s) => s.id == _selectedSiteId);

  ReferenceItem? get _selectedContract =>
      _contracts.firstWhereOrNull((c) => c.id == _selectedContractId);

  ZoneItem? get _selectedZone =>
      _zones.firstWhereOrNull((z) => z.id == _selectedZoneId);

  // ── Cycle de vie ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _applyFallbackReferences();
    unawaited(_loadReferences());
    unawaited(_restoreDraft());
    unawaited(_initConnectivity());

    if (!kIsWeb) unawaited(_initSpeech());

    _descriptionController.addListener(_scheduleDraftSave);
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _connectivitySub.cancel();
    _userWantsToListen = false;
    _descriptionController.removeListener(_scheduleDraftSave);
    _descriptionController.dispose();
    _speech.stop();
    super.dispose();
  }

  // ── Connectivité ─────────────────────────────────────────────────────────

  Future<void> _initConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(
          () => _isOffline = results.every((r) => r == ConnectivityResult.none));
    }

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (offline != _isOffline && mounted) {
        setState(() => _isOffline = offline);
        if (!offline) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Connexion retablie !')),
          );
        }
      }
    });
  }

  // ── Brouillon ─────────────────────────────────────────────────────────────

  void _scheduleDraftSave() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(seconds: 2), _saveDraft);
  }

  Future<void> _saveDraft() async {
    await _draftService.saveDraft(
      FormDraft(
        siteId: _selectedSiteId,
        contractId: _selectedContractId,
        zoneId: _selectedZoneId,
        description: _descriptionController.text,
      ),
    );
  }

  Future<void> _restoreDraft() async {
    final draft = await _draftService.loadDraft();
    if (draft == null || draft.isEmpty || !mounted) return;

    setState(() {
      if (draft.siteId != null) _selectedSiteId = draft.siteId;
      if (draft.contractId != null) _selectedContractId = draft.contractId;
      if (draft.zoneId != null) _selectedZoneId = draft.zoneId;
      if (draft.description.isNotEmpty) {
        _descriptionController.text = draft.description;
        _committedText = draft.description;
      }
      _hasDraftRestored = draft.description.isNotEmpty;
    });
  }

  Future<void> _clearDraft() async {
    await _draftService.clearDraft();
    _draftSaveTimer?.cancel();
  }

  // ── Références ────────────────────────────────────────────────────────────

  List<ZoneItem> _buildFallbackZones({
    required String? siteId,
    required String? contractId,
  }) {
    return _fallbackZones
        .where((z) => z.siteId == siteId && z.contractId == contractId)
        .toList();
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
    } on AuthExpiredException {
      if (mounted) widget.onSessionExpired();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'References indisponibles — mode local actif.\n${error.message}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Impossible de synchroniser les references — mode local actif.';
      });
    } finally {
      if (mounted) setState(() => _isSyncingReferences = false);
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
    } on AuthExpiredException {
      if (mounted) widget.onSessionExpired();
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
      if (mounted) setState(() => _isLoadingZones = false);
    }
  }

  // ── Dictée vocale ─────────────────────────────────────────────────────────

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
              setState(() => _isListening = false);
            } else {
              _committedText = _descriptionController.text.trim();
              unawaited(_startListening());
            }
          } else {
            setState(() => _isListening = false);
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
          setState(() => _isListening = false);
        }
      },
    );

    if (mounted) setState(() => _speechReady = available);
  }

  Future<void> _startListening() async {
    if (!mounted) return;

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
        if (mySession != _listenSession) return;

        final newWords = result.recognizedWords.trim();
        if (newWords.isNotEmpty) _lastSpeechTime = DateTime.now();

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

    if (mounted) setState(() => _isListening = true);
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
      if (mounted) setState(() => _isListening = false);
      return;
    }

    _userWantsToListen = true;
    _committedText = _descriptionController.text.trim();
    _lastSpeechTime = DateTime.now();
    await _startListening();
  }

  // ── Templates ─────────────────────────────────────────────────────────────

  void _showTemplates() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _TemplatesSheet(
        onSelect: (phrase) {
          final current = _descriptionController.text;
          final separator =
              current.isNotEmpty && !current.endsWith(' ') ? ' ' : '';
          _descriptionController.text = '$current$separator$phrase';
          _descriptionController.selection = TextSelection.fromPosition(
            TextPosition(offset: _descriptionController.text.length),
          );
          _committedText = _descriptionController.text.trim();
          Navigator.of(context).pop();
        },
      ),
    );
  }

  // ── Soumission ────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    // Vérifier la connectivité
    if (_isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hors ligne — votre description est sauvegardee localement. '
            'Reconnectez-vous pour envoyer.',
          ),
        ),
      );
      return;
    }

    final site = _selectedSite;
    final contract = _selectedContract;
    final zone = _selectedZone;
    final description = _descriptionController.text.trim();

    if (site == null || contract == null || zone == null) {
      setState(() => _errorMessage = 'Choisis le site, le contrat et la zone.');
      return;
    }
    if (description.isEmpty) {
      setState(
          () => _errorMessage = 'Ajoute une description ou utilise le micro.');
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

      // Brouillon effacé seulement après succès
      unawaited(_clearDraft());

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReportResultPage(
            initialRows: result.rows,
            rawModelOutput: result.rawModelOutput,
          ),
        ),
      );
    } on AuthExpiredException {
      if (mounted) widget.onSessionExpired();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage =
          'Extraction impossible. Verifie le backend puis reessaie.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Nouveau releve',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(widget.session.fullName, style: theme.textTheme.bodySmall),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Historique',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HistoryPage()),
            ),
            icon: const Icon(Icons.history_rounded),
          ),
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
            // ── Bandeau hors-ligne ────────────────────────────────────────
            if (_isOffline) ...<Widget>[
              _buildOfflineBanner(theme),
              const SizedBox(height: 8),
            ],
            // ── Bandeau brouillon restauré ────────────────────────────────
            if (_hasDraftRestored) ...<Widget>[
              _buildDraftBanner(theme),
              const SizedBox(height: 8),
            ],
            // ── Site ──────────────────────────────────────────────────────
            _DropdownCard(
              label: 'Site',
              icon: Icons.location_on_outlined,
              isLoading: _isSyncingReferences,
              value: _selectedSiteId,
              items:
                  _sites.map((s) => _DropdownEntry(id: s.id, name: s.name)).toList(),
              onChanged: (value) async {
                setState(() => _selectedSiteId = value);
                _scheduleDraftSave();
                await _loadZones();
              },
            ),
            const SizedBox(height: 12),
            // ── Contrat ───────────────────────────────────────────────────
            _DropdownCard(
              label: 'Contrat',
              icon: Icons.description_outlined,
              isLoading: _isSyncingReferences,
              value: _selectedContractId,
              items: _contracts
                  .map((c) => _DropdownEntry(id: c.id, name: c.name))
                  .toList(),
              onChanged: (value) async {
                setState(() => _selectedContractId = value);
                _scheduleDraftSave();
                await _loadZones();
              },
            ),
            const SizedBox(height: 12),
            // ── Zone ──────────────────────────────────────────────────────
            _DropdownCard(
              label: 'Zone',
              icon: Icons.map_outlined,
              isLoading: _isLoadingZones,
              value: _selectedZoneId,
              items: _zones
                  .map((z) => _DropdownEntry(id: z.id, name: z.name))
                  .toList(),
              onChanged: (value) {
                setState(() => _selectedZoneId = value);
                _scheduleDraftSave();
              },
            ),
            const SizedBox(height: 20),
            // ── Description + Micro ───────────────────────────────────────
            _buildDescriptionCard(theme),
            const SizedBox(height: 20),
            // ── Actions ───────────────────────────────────────────────────
            _buildActionButtons(),
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 16),
              _buildErrorBox(),
            ],
          ],
        ),
      ),
    );
  }

  // ── Widgets auxiliaires ───────────────────────────────────────────────────

  Widget _buildOfflineBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.wifi_off_rounded, color: Color(0xFFD97706), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Hors ligne — votre saisie est sauvegardee automatiquement.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBE4D8)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.restore_rounded, color: Color(0xFF0F766E), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Brouillon restaure depuis la derniere session.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF0F766E),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              _descriptionController.clear();
              _committedText = '';
              unawaited(_clearDraft());
              setState(() => _hasDraftRestored = false);
            },
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            child: const Text('Effacer', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Header : icône + titre + bouton micro
            Row(
              children: <Widget>[
                const Icon(
                  Icons.edit_note_rounded,
                  size: 18,
                  color: Color(0xFF0F766E),
                ),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
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
            // Indicateur enregistrement
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
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: const Color(0xFF0F766E)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            // Champ de texte
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
            const SizedBox(height: 12),
            // Bouton templates
            OutlinedButton.icon(
              onPressed: _showTemplates,
              style: OutlinedButton.styleFrom(
                minimumSize: Size.zero,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              icon: const Icon(Icons.bolt_rounded, size: 16),
              label: const Text(
                'Phrases rapides',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              _descriptionController.clear();
              _committedText = '';
              unawaited(_clearDraft());
              setState(() {
                _hasDraftRestored = false;
                _errorMessage = null;
              });
            },
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Effacer'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: (_isSubmitting || _isOffline) ? null : _submit,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    _isOffline
                        ? Icons.wifi_off_rounded
                        : Icons.check_rounded,
                  ),
            label: Text(_isSubmitting
                ? 'Extraction...'
                : _isOffline
                    ? 'Hors ligne'
                    : 'Valider'),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBox() {
    return Container(
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
    );
  }
}

// ── Feuille des templates ────────────────────────────────────────────────────

class _TemplatesSheet extends StatelessWidget {
  const _TemplatesSheet({required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.bolt_rounded, color: Color(0xFF0F766E)),
              const SizedBox(width: 8),
              Text(
                'Phrases rapides',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Appuie sur une phrase pour l\'ajouter à la description.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF526965),
                ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _phraseTemplates
                .map(
                  (phrase) => ActionChip(
                    label: Text(phrase),
                    onPressed: () => onSelect(phrase),
                    backgroundColor: const Color(0xFFEAF6F2),
                    side: const BorderSide(color: Color(0xFFBBE4D8)),
                    labelStyle: const TextStyle(
                      color: Color(0xFF0F766E),
                      fontSize: 13,
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

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
              initialValue: safeValue,
              isExpanded: true,
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

// ── Extension utilitaire ─────────────────────────────────────────────────────

extension _ListFirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
