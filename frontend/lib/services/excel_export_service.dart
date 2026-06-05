import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/report_models.dart';

// ── Résultat d'un export ──────────────────────────────────────────────────────

/// Contient les deux chemins produits lors d'un export :
/// - [sharePath]  : copie dans le cache (pour share_plus).
/// - [savedPath]  : copie persistante dans le stockage externe de l'app.
class ExportResult {
  const ExportResult({required this.sharePath, required this.savedPath});

  /// Chemin utilisé pour le partage (cache temporaire).
  final String sharePath;

  /// Chemin permanent — visible dans le gestionnaire de fichiers Android :
  /// Stockage interne > Android > data > [app] > files > VoiceToSheet
  final String savedPath;

  String get fileName => sharePath.split('/').last;
  bool get isZip => sharePath.endsWith('.zip');
}

// ── Service ───────────────────────────────────────────────────────────────────

/// Génère le fichier de rapport et permet de le partager par email.
///
/// • Sans photos → un seul `.xlsx` en pièce jointe.
/// • Avec photos  → un seul `.zip` contenant le `.xlsx` (colonne Photo
///   renseignée) et un dossier `photos/`.
///
/// Dans tous les cas le fichier est sauvegardé dans :
///   Stockage > Android/data/[app]/files/VoiceToSheet/
class ExcelExportService {
  // ── API principale ────────────────────────────────────────────────────────

  /// Génère le fichier, le sauvegarde de façon persistante et retourne
  /// un [ExportResult] avec le chemin de partage et le chemin sauvegardé.
  Future<ExportResult> generateExportFile(
    List<EquipmentRow> rows, {
    Map<int, String> photoPaths = const <int, String>{},
  }) async {
    final now = DateTime.now();
    final stamp =
        '${now.year}${_pad(now.month)}${_pad(now.day)}'
        '_${_pad(now.hour)}${_pad(now.minute)}';
    final xlsxName = 'releve_terrain_$stamp.xlsx';

    final excelBytes = _buildExcelBytes(rows, photoPaths: photoPaths);

    late List<int> fileBytes;
    late String fileName;

    if (photoPaths.isEmpty) {
      fileBytes = excelBytes;
      fileName = xlsxName;
    } else {
      // Construire le ZIP
      final archive = Archive();
      archive.addFile(
        ArchiveFile(xlsxName, excelBytes.length, excelBytes),
      );
      for (final entry in photoPaths.entries) {
        final f = File(entry.value);
        if (!f.existsSync()) continue;
        final bytes = await f.readAsBytes();
        final name = entry.value.split('/').last;
        archive.addFile(ArchiveFile('photos/$name', bytes.length, bytes));
      }
      fileBytes = ZipEncoder().encode(archive)!;
      fileName = 'releve_terrain_$stamp.zip';
    }

    // ── Sauvegarde dans le cache (pour share_plus) ────────────────────────
    final cacheDir = await getTemporaryDirectory();
    final sharePath = '${cacheDir.path}/$fileName';
    await File(sharePath).writeAsBytes(fileBytes, flush: true);

    // ── Sauvegarde persistante (pour l'agent) ─────────────────────────────
    final persistDir = await _getPersistentDir();
    final savedPath = '${persistDir.path}/$fileName';
    await File(savedPath).writeAsBytes(fileBytes, flush: true);

    return ExportResult(sharePath: sharePath, savedPath: savedPath);
  }

  // ── Partage ───────────────────────────────────────────────────────────────

  Future<void> shareFile({required ExportResult result}) async {
    final now = DateTime.now();
    final dateLabel = '${_pad(now.day)}/${_pad(now.month)}/${now.year}';

    final mimeType =
        result.isZip ? 'application/zip' : _xlsxMime;

    final photoNote = result.isZip
        ? '\nLes photos sont dans le dossier photos/ de l\'archive ZIP.'
        : '';

    await Share.shareXFiles(
      <XFile>[
        XFile(result.sharePath, mimeType: mimeType, name: result.fileName),
      ],
      subject: 'Releve terrain du $dateLabel — VoiceToSheet',
      text:
          'Bonjour,\n\n'
          'Veuillez trouver en piece jointe le releve terrain du $dateLabel '
          'exporte depuis l\'application VoiceToSheet.$photoNote\n\n'
          'Cordialement.',
    );
  }

  // ── Construction Excel ────────────────────────────────────────────────────

  List<int> _buildExcelBytes(
    List<EquipmentRow> rows, {
    required Map<int, String> photoPaths,
  }) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet()!;
    excel.rename(defaultSheet, 'Releve terrain');
    final sheet = excel['Releve terrain'];

    final hasPhotos = photoPaths.isNotEmpty;
    final headers = <String>[
      'Site', 'Contrat', 'Zone', 'Nom equipement', 'Details',
      if (hasPhotos) 'Photo',
    ];

    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = CellStyle(bold: true);
    }

    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      final photoName =
          photoPaths.containsKey(r) ? photoPaths[r]!.split('/').last : '';

      final values = <String>[
        row.site, row.contrat, row.zone, row.equipement, row.description,
        if (hasPhotos) photoName,
      ];

      for (var c = 0; c < values.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
            .value = TextCellValue(values[c]);
      }
    }

    return excel.encode()!;
  }

  // ── Répertoire persistant ─────────────────────────────────────────────────

  /// Retourne le dossier de sauvegarde persistante.
  /// Priorité : stockage externe de l'app > stockage interne.
  /// Crée le sous-dossier `VoiceToSheet/` si nécessaire.
  Future<Directory> _getPersistentDir() async {
    // Stockage externe de l'app (visible dans le gestionnaire de fichiers) :
    // /storage/emulated/0/Android/data/<package>/files/VoiceToSheet
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        final dir = Directory('${ext.path}/VoiceToSheet');
        await dir.create(recursive: true);
        return dir;
      }
    } catch (_) {}

    // Fallback : stockage interne de l'app.
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/VoiceToSheet');
    await dir.create(recursive: true);
    return dir;
  }

  // ── Utilitaires ───────────────────────────────────────────────────────────

  static const String _xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  String _pad(int n) => n.toString().padLeft(2, '0');
}
