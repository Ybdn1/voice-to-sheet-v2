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

  ReferenceItem? get _selectedSite {
    for (final item in _sites) {
      if (item.id == _selectedSiteId) {
        return item;
      }
    }
    return null;
  }

  ReferenceItem? get _selectedContract {
    for (final item in _contracts) {
      if (item.id == _selectedContractId) {
        return item;
      }
    }
    return null;
  }

  ZoneItem? get _selectedZone {
    for (final item in _zones) {
      if (item.id == _selectedZoneId) {
        return item;
      }
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

      if (!mounted) {
        return;
      }

      setState(() {
        _sites = results[0] as List<ReferenceItem>;
        _contracts = results[1] as List<ReferenceItem>;
        _selectedSiteId = _sites.any((site) => site.id == _selectedSiteId)
            ? _selectedSiteId
            : (_sites.isNotEmpty ? _sites.first.id : null);
        _selectedContractId = _contracts.any((contract) => contract.id == _selectedContractId)
            ? _selectedContractId
            : (_contracts.isNotEmpty ? _contracts.first.id : null);
      });

      await _loadZones();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'References backend indisponibles. Mode local actif.\n${error.message}';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Impossible de synchroniser les references. Mode local actif.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingReferences = false;
        });
      }
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

      if (!mounted) {
        return;
      }

      setState(() {
        _zones = zones;
        _selectedZoneId = zones.isNotEmpty ? zones.first.id : null;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Zones backend indisponibles. Mode local actif.\n${error.message}';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Impossible de synchroniser les zones. Mode local actif.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingZones = false;
        });
      }
    }
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          if (_userWantsToListen) {
            // Verifie si le silence dure depuis plus de 5 minutes.
            final lastSpeech = _lastSpeechTime;
            final silenceTooLong = lastSpeech != null &&
                DateTime.now().difference(lastSpeech) >= _silenceTimeout;

            if (silenceTooLong) {
              // 5 minutes sans parole → arret automatique propre.
              _userWantsToListen = false;
              _committedText = '';
              _lastSpeechTime = null;
              setState(() { _isListening = false; });
            } else {
              // Android a coupe (pause courte ou limite de session) mais
              // l'agent n'a pas encore atteint 5 min de silence → on relance.
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
          // En cas d'erreur passagere, on retente apres un court delai.
          _committedText = _descriptionController.text.trim();
          Future<void>.delayed(const Duration(milliseconds: 500), () {
            if (_userWantsToListen && mounted) {
              unawaited(_startListening());
            }
          });
        } else {
          setState(() { _isListening = false; });
        }
      },
    );

    if (mounted) {
      setState(() {
        _speechReady = available;
      });
    }
  }

  Future<void> _startListening() async {
    if (!mounted) return;

    await _speech.listen(
      localeId: 'fr_FR',
      listenFor: const Duration(minutes: 2),
      pauseFor: const Duration(seconds: 20),
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
      ),
      onResult: (result) {
        final newWords = result.recognizedWords.trim();
        if (newWords.isNotEmpty) {
          // Un mot a ete capte → on remet le compteur de silence a zero.
          _lastSpeechTime = DateTime.now();
        }
        // On concatene le texte deja valide avec les nouveaux mots reconnus.
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

    if (mounted) {
      setState(() {
        _isListening = true;
      });
    }
  }

  Future<void> _toggleListening() async {
    if (!_speechReady) {
      await _initSpeech();
    }

    if (!_speechReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La dictee native est indisponible sur cet appareil.'),
        ),
      );
      return;
    }

    if (_isListening || _userWantsToListen) {
      // L'agent arrete manuellement → on stoppe tout sans relancer.
      _userWantsToListen = false;
      _committedText = '';
      _lastSpeechTime = null;
      await _speech.stop();
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }
      return;
    }

    // Demarre la dictee longue duree.
    _userWantsToListen = true;
    _committedText = _descriptionController.text.trim();
    _lastSpeechTime = DateTime.now(); // demarre le compteur de silence
    await _startListening();
  }

  Future<void> _submit() async {
    final site = _selectedSite;
    final contract = _selectedContract;
    final zone = _selectedZone;
    final description = _descriptionController.text.trim();

    if (site == null || contract == null || zone == null) {
      setState(() {
        _errorMessage = 'Choisis le site, le contrat et la zone.';
      });
      return;
    }

    if (description.isEmpty) {
      setState(() {
        _errorMessage = 'Ajoute une description ou utilise le micro.';
      });
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

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReportResultPage(
            initialRows: result.rows,
            rawModelOutput: result.rawModelOutput,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Extraction impossible. Verifie le backend puis reessaie.';
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
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Nouveau releve',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              widget.session.fullName,
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFFFFF2B3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Ecran de saisie actif',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('API: ${widget.api.baseUrl}'),
                  Text('Sites charges: ${_sites.length}'),
                  Text('Contrats charges: ${_contracts.length}'),
                  Text('Zones chargees: ${_zones.length}'),
                  Text('Sync backend: ${_isSyncingReferences ? "en cours" : "terminee"}'),
                  Text('Zones en chargement: ${_isLoadingZones ? "oui" : "non"}'),
                  if (kIsWeb) const Text('Mode web: micro desactive'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: const Color(0xFFE3F4F1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Bouton pour parler',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    kIsWeb
                        ? 'La dictee vocale n est pas active dans cet apercu web. Lance l app sur Android pour parler.'
                        : 'Appuie sur le bouton ci-dessous puis parle naturellement.',
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: kIsWeb ? null : _toggleListening,
                      icon: Icon(
                        _isListening
                            ? Icons.stop_circle_outlined
                            : Icons.mic_none_rounded,
                      ),
                      label: Text(
                        kIsWeb
                            ? 'Micro disponible sur Android'
                            : (_isListening ? 'Arreter la dictee' : 'Parler maintenant'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SimpleSection(
              title: '1. Site',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _sites
                    .map(
                      (site) => ChoiceChip(
                        label: Text(site.name),
                        selected: _selectedSiteId == site.id,
                        onSelected: (selected) async {
                          if (!selected) {
                            return;
                          }
                          setState(() {
                            _selectedSiteId = site.id;
                          });
                          await _loadZones();
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
            _SimpleSection(
              title: '2. Contrat',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _contracts
                    .map(
                      (contract) => ChoiceChip(
                        label: Text(contract.name),
                        selected: _selectedContractId == contract.id,
                        onSelected: (selected) async {
                          if (!selected) {
                            return;
                          }
                          setState(() {
                            _selectedContractId = contract.id;
                          });
                          await _loadZones();
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
            _SimpleSection(
              title: '3. Zone',
              child: _zones.isEmpty
                  ? const Text('Aucune zone disponible.')
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _zones
                          .map(
                            (zone) => ChoiceChip(
                              label: Text(zone.name),
                              selected: _selectedZoneId == zone.id,
                              onSelected: (selected) {
                                if (!selected) {
                                  return;
                                }
                                setState(() {
                                  _selectedZoneId = zone.id;
                                });
                              },
                            ),
                          )
                          .toList(),
                    ),
            ),
            const SizedBox(height: 16),
            _SimpleSection(
              title: '4. Description libre',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    kIsWeb
                        ? 'Saisie texte seulement dans le navigateur.'
                        : 'Tu peux utiliser le gros bouton micro plus haut ou saisir au clavier.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    minLines: 6,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText:
                          'Exemple: reservoir eaux brutes avec 3 pompes, pompe 1 cassee, pompe 2 50DN...',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      _descriptionController.clear();
                      setState(() {});
                    },
                    child: const Text('Effacer'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: Text(_isSubmitting ? 'Extraction...' : 'Valider'),
                  ),
                ),
              ],
            ),
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                color: const Color(0xFFFFD7D7),
                child: Text(_errorMessage!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SimpleSection extends StatelessWidget {
  const _SimpleSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
