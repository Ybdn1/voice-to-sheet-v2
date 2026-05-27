import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/report_models.dart';
import '../services/google_sheet_service.dart';

class ReportResultPage extends StatefulWidget {
  const ReportResultPage({
    super.key,
    required this.initialRows,
    required this.rawModelOutput,
  });

  final List<EquipmentRow> initialRows;
  final String rawModelOutput;

  @override
  State<ReportResultPage> createState() => _ReportResultPageState();
}

class _ReportResultPageState extends State<ReportResultPage> {
  late List<_EditableEquipmentRow> _rows;
  late final GoogleSheetService _googleSheetService;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _googleSheetService = GoogleSheetService();
    _rows = widget.initialRows
        .map((row) => _EditableEquipmentRow.fromEquipmentRow(row))
        .toList();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  List<EquipmentRow> get _currentRows {
    return _rows.map((row) => row.toEquipmentRow()).toList();
  }

  Future<void> _copyJson() async {
    final payload = JsonEncoder.withIndent('  ').convert(
      _currentRows.map((row) => row.toJson()).toList(),
    );

    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('JSON copie dans le presse-papiers.')),
    );
  }

  void _addRow() {
    final source = _currentRows.isNotEmpty ? _currentRows.first : null;

    setState(() {
      _rows = <_EditableEquipmentRow>[
        ..._rows,
        _EditableEquipmentRow(
          site: source?.site ?? '',
          contrat: source?.contrat ?? '',
          zone: source?.zone ?? '',
          equipementController: TextEditingController(),
          descriptionController: TextEditingController(),
        ),
      ];
    });
  }

  void _removeRow(int index) {
    final row = _rows[index];
    row.dispose();
    setState(() {
      _rows = List<_EditableEquipmentRow>.from(_rows)..removeAt(index);
    });
  }

  void _showRawOutput() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sortie brute du modele'),
          content: SingleChildScrollView(
            child: SelectableText(widget.rawModelOutput),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportGoogleSheet() async {
    if (_isExporting) {
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final createdSheet = await _googleSheetService.createSheet(_currentRows);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google Sheet creee : ${createdSheet.title}'),
          action: SnackBarAction(
            label: 'Ouvrir',
            onPressed: () {
              _openUrl(createdSheet.url);
            },
          ),
        ),
      );

      final action = await showDialog<_SheetAfterExportAction>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Google Sheet creee'),
            content: const Text(
              'Veux-tu preparer un mail au chef avec le lien de la feuille ?',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(_SheetAfterExportAction.later),
                child: const Text('Plus tard'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(_SheetAfterExportAction.open),
                child: const Text('Ouvrir'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(_SheetAfterExportAction.email),
                child: const Text('Oui'),
              ),
            ],
          );
        },
      );

      if (action == _SheetAfterExportAction.open) {
        await _openUrl(createdSheet.url);
      } else if (action == _SheetAfterExportAction.email) {
        await _openMailDraft(createdSheet);
      }
    } on UnsupportedError catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? error.toString())),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export impossible : $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _openMailDraft(CreatedGoogleSheet sheet) async {
    final uri = Uri(
      scheme: 'mailto',
      queryParameters: <String, String>{
        'subject': 'VoiceToSheet - feuille terrain',
        'body':
            'Bonjour,\n\nVoici le lien vers la Google Sheet VoiceToSheet '
            'cree depuis le terrain :\n${sheet.url}\n\nMerci.',
      },
    );

    final launched = await launchUrl(uri);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible d ouvrir l application mail sur cet appareil.',
          ),
        ),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Le brouillon mail est ouvert. Il reste juste a renseigner l adresse du chef.',
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final launched = await launchUrl(Uri.parse(url));
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d ouvrir la Google Sheet.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification du releve'),
        actions: <Widget>[
          IconButton(
            onPressed: _showRawOutput,
            tooltip: 'Voir la sortie brute',
            icon: const Icon(Icons.code_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF6F2),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.checklist_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${_rows.length} lignes extraites',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Corrige les equipements ou ajoute une ligne avant export.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: _rows.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final row = _rows[index];

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Text(
                                'Ligne ${index + 1}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: () => _removeRow(index),
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ],
                          ),
                          Text(
                            '${row.site}  |  ${row.contrat}  |  ${row.zone}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF61736F),
                                ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: row.equipementController,
                            decoration: const InputDecoration(
                              labelText: 'Equipement',
                              prefixIcon: Icon(Icons.precision_manufacturing_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: row.descriptionController,
                            decoration: const InputDecoration(
                              labelText: 'Etat ou caracteristique',
                              prefixIcon: Icon(Icons.edit_note_rounded),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Ajouter une ligne'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _copyJson,
                          icon: const Icon(Icons.copy_all_rounded),
                          label: const Text('Copier JSON'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isExporting ? null : _exportGoogleSheet,
                          icon: _isExporting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.cloud_upload_rounded),
                          label: Text(
                            _isExporting ? 'Export...' : 'Google Sheet',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SheetAfterExportAction {
  later,
  open,
  email,
}

class _EditableEquipmentRow {
  _EditableEquipmentRow({
    required this.site,
    required this.contrat,
    required this.zone,
    required this.equipementController,
    required this.descriptionController,
  });

  final String site;
  final String contrat;
  final String zone;
  final TextEditingController equipementController;
  final TextEditingController descriptionController;

  factory _EditableEquipmentRow.fromEquipmentRow(EquipmentRow row) {
    return _EditableEquipmentRow(
      site: row.site,
      contrat: row.contrat,
      zone: row.zone,
      equipementController: TextEditingController(text: row.equipement),
      descriptionController: TextEditingController(text: row.description),
    );
  }

  EquipmentRow toEquipmentRow() {
    return EquipmentRow(
      site: site,
      contrat: contrat,
      zone: zone,
      equipement: equipementController.text.trim(),
      description: descriptionController.text.trim(),
    );
  }

  void dispose() {
    equipementController.dispose();
    descriptionController.dispose();
  }
}
