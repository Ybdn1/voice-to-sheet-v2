import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/history_models.dart';
import '../models/report_models.dart';
import '../services/excel_export_service.dart';
import '../services/history_service.dart';

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

  final ExcelExportService _excelService = ExcelExportService();
  final HistoryService _historyService = HistoryService();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
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

  List<EquipmentRow> get _currentRows =>
      _rows.map((r) => r.toEquipmentRow()).toList();

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _copyJson() async {
    final payload = JsonEncoder.withIndent('  ').convert(
      _currentRows.map((r) => r.toJson()).toList(),
    );
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
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

  /// Ajoute ou remplace la photo d'une ligne.
  Future<void> _pickPhoto(int index, ImageSource source) async {
    try {
      final file = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1920,
      );
      if (file == null || !mounted) return;

      setState(() => _rows[index].photoPath = file.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d\'acceder a l\'appareil photo : $error')),
      );
    }
  }

  void _showPhotoSourceMenu(BuildContext context, int index) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Prendre une photo'),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_pickPhoto(index, ImageSource.camera));
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choisir dans la galerie'),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_pickPhoto(index, ImageSource.gallery));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _removePhoto(int index) {
    setState(() => _rows[index].photoPath = null);
  }

  void _showRawOutput() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
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
      ),
    );
  }

  // ── Export Excel + email ──────────────────────────────────────────────────

  Future<void> _exportExcel() async {
    if (_isExporting) return;

    setState(() => _isExporting = true);

    try {
      final rows = _currentRows;

      // 1. Construire la map index → chemin photo
      final photoMap = <int, String>{};
      for (var i = 0; i < _rows.length; i++) {
        final path = _rows[i].photoPath;
        if (path != null) photoMap[i] = path;
      }

      // 2. Générer le fichier (xlsx seul OU zip si photos)
      final result = await _excelService.generateExportFile(
        rows,
        photoPaths: photoMap,
      );

      if (!mounted) return;

      // Chemin lisible pour le snackbar
      final friendlyPath = _friendlyPath(result.savedPath);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isZip
                ? 'Archive ZIP sauvegardee !\n$friendlyPath'
                : 'Fichier Excel sauvegarde !\n$friendlyPath',
          ),
          duration: const Duration(seconds: 4),
        ),
      );

      // 3. Sauvegarder dans l'historique
      if (rows.isNotEmpty) {
        final firstRow = rows.first;
        unawaited(
          _historyService.addEntry(
            HistoryEntry(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              date: DateTime.now(),
              site: firstRow.site,
              contrat: firstRow.contrat,
              zone: firstRow.zone,
              rows: rows,
            ),
          ),
        );
      }

      // 4. Demander ce que l'agent veut faire avec le fichier
      final action = await showDialog<_ExportAction>(
        context: context,
        builder: (context) => _ExportActionDialog(
          isZip: result.isZip,
          nbPhotos: photoMap.length,
        ),
      );

      // 5. Ouvrir le sélecteur de partage selon l'action choisie
      if (action != null && action != _ExportAction.later && mounted) {
        await _excelService.shareFile(result: result);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export impossible : $error')),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
            // ── Bandeau résumé ────────────────────────────────────────────
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
                      child: const Icon(
                        Icons.checklist_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${_rows.length} ligne${_rows.length > 1 ? 's' : ''} extraite${_rows.length > 1 ? 's' : ''}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Corrige ou ajoute une photo avant export.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ── Liste des lignes ──────────────────────────────────────────
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: _rows.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    _buildRowCard(context, index),
              ),
            ),
            // ── Barre d'actions ───────────────────────────────────────────
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
                          onPressed: _isExporting ? null : _exportExcel,
                          icon: _isExporting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.table_chart_rounded),
                          label: Text(
                            _isExporting ? 'Export...' : 'Export Excel',
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

  Widget _buildRowCard(BuildContext context, int index) {
    final row = _rows[index];
    final hasPhoto = row.photoPath != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // En-tête ligne
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
            // Champ équipement
            TextFormField(
              controller: row.equipementController,
              decoration: const InputDecoration(
                labelText: 'Equipement',
                prefixIcon: Icon(Icons.precision_manufacturing_outlined),
              ),
            ),
            const SizedBox(height: 12),
            // Champ description
            TextFormField(
              controller: row.descriptionController,
              decoration: const InputDecoration(
                labelText: 'Etat ou caracteristique',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
            ),
            const SizedBox(height: 14),
            // Zone photo
            if (hasPhoto) ...<Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(row.photoPath!),
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildPhotoPlaceholder(row.photoPath!),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 14,
                    color: Color(0xFF0F766E),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      row.photoPath!.split('/').last,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF526965),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _removePhoto(index),
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      foregroundColor: const Color(0xFFDC2626),
                    ),
                    child: const Text(
                      'Supprimer',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
            // Bouton ajouter/changer photo
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () => _showPhotoSourceMenu(context, index),
              style: OutlinedButton.styleFrom(
                minimumSize: Size.zero,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              icon: Icon(
                hasPhoto
                    ? Icons.camera_alt_outlined
                    : Icons.add_a_photo_outlined,
                size: 16,
              ),
              label: Text(
                hasPhoto ? 'Changer la photo' : 'Ajouter une photo',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Raccourcit le chemin pour l'affichage dans le snackbar.
  String _friendlyPath(String path) {
    // Affiche les 3 derniers segments : ex. "files/VoiceToSheet/releve_...xlsx"
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.length > 3
        ? '.../${parts.sublist(parts.length - 3).join('/')}'
        : path;
  }

  Widget _buildPhotoPlaceholder(String path) {
    // Affichage de secours si l'image ne peut pas être rendue
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(
            Icons.image_outlined,
            color: Color(0xFF0F766E),
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            path.split('/').last,
            style: const TextStyle(fontSize: 12, color: Color(0xFF526965)),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

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

  /// Chemin local vers la photo prise pour cet équipement (nullable).
  String? photoPath;

  factory _EditableEquipmentRow.fromEquipmentRow(EquipmentRow row) {
    return _EditableEquipmentRow(
      site: row.site,
      contrat: row.contrat,
      zone: row.zone,
      equipementController: TextEditingController(text: row.equipement),
      descriptionController: TextEditingController(text: row.description),
    );
  }

  EquipmentRow toEquipmentRow() => EquipmentRow(
        site: site,
        contrat: contrat,
        zone: zone,
        equipement: equipementController.text.trim(),
        description: descriptionController.text.trim(),
      );

  void dispose() {
    equipementController.dispose();
    descriptionController.dispose();
  }
}

// ── Dialog "Que faire avec le fichier ?" ──────────────────────────────────────

enum _ExportAction { drive, email, later }

class _ExportActionDialog extends StatelessWidget {
  const _ExportActionDialog({required this.isZip, required this.nbPhotos});

  final bool isZip;
  final int nbPhotos;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF6F2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.table_chart_rounded,
              color: Color(0xFF0F766E),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('Que faire avec le fichier ?')),
        ],
      ),
      content: Text(
        isZip
            ? 'Archive ZIP sauvegardee sur le telephone.\n'
                'Contient le tableau Excel + $nbPhotos photo(s).\n\n'
                'Choisissez une action :'
            : 'Fichier Excel sauvegarde sur le telephone.\n\n'
                'Choisissez une action :',
      ),
      // Boutons empilés verticalement pour plus de lisibilité
      actionsAlignment: MainAxisAlignment.center,
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: <Widget>[
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_ExportAction.drive),
          icon: const Icon(Icons.cloud_upload_outlined, size: 18),
          label: const Text('Sauvegarder sur Drive'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1A73E8),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_ExportAction.email),
          icon: const Icon(Icons.send_rounded, size: 18),
          label: const Text('Envoyer au chef par email'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_ExportAction.later),
          child: const Text('Plus tard'),
        ),
      ],
    );
  }
}
