import 'dart:async';

import 'package:flutter/material.dart';

import '../models/history_models.dart';
import '../services/excel_export_service.dart';
import '../services/history_service.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final HistoryService _historyService = HistoryService();
  final ExcelExportService _excelService = ExcelExportService();

  List<HistoryEntry> _entries = <HistoryEntry>[];
  bool _isLoading = true;
  String? _exportingId;

  @override
  void initState() {
    super.initState();
    unawaited(_loadEntries());
  }

  Future<void> _loadEntries() async {
    final entries = await _historyService.loadHistory();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _isLoading = false;
    });
  }

  Future<void> _delete(HistoryEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce relevé ?'),
        content: Text(
          'Relevé du ${_formatDate(entry.date)} — ${entry.site}\n'
          'Cette action est irréversible.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    await _historyService.deleteEntry(entry.id);
    if (!mounted) return;
    setState(() => _entries.removeWhere((e) => e.id == entry.id));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Relevé supprimé.')),
    );
  }

  Future<void> _reExport(HistoryEntry entry) async {
    if (_exportingId != null) return;
    setState(() => _exportingId = entry.id);

    try {
      final result = await _excelService.generateExportFile(entry.rows);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fichier sauvegarde !\n.../${result.savedPath.split('/').reversed.take(3).toList().reversed.join('/')}'),
          duration: const Duration(seconds: 3),
        ),
      );

      final sendToChef = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF6F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.mark_email_read_outlined,
                  color: Color(0xFF0F766E),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('Envoyer au chef ?')),
            ],
          ),
          content: const Text(
            'Fichier Excel genere. Voulez-vous l\'envoyer par email ?\n\n'
            'L\'app mail s\'ouvrira avec le fichier en piece jointe.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Non, merci'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Oui, envoyer'),
            ),
          ],
        ),
      );

      if (sendToChef == true && mounted) {
        await _excelService.shareFile(result: result);
      }

    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export impossible : $error')),
      );
    } finally {
      if (mounted) setState(() => _exportingId = null);
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vider tout l\'historique ?'),
        content: const Text('Tous les relevés sauvegardés seront supprimés.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Vider'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    await _historyService.clearAll();
    if (!mounted) return;
    setState(() => _entries = <HistoryEntry>[]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique des relevés'),
        actions: <Widget>[
          if (_entries.isNotEmpty)
            IconButton(
              tooltip: 'Tout effacer',
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? _buildEmpty(context)
              : _buildList(context),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.history_rounded,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Aucun relevé exporté pour l\'instant.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF526965),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: _entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final isExporting = _exportingId == entry.id;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF6F2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.table_chart_rounded,
                        color: Color(0xFF0F766E),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _formatDate(entry.date),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '${entry.site}  ·  ${entry.contrat}  ·  ${entry.zone}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF526965),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F4F1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${entry.nbRows} ligne${entry.nbRows > 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isExporting ? null : () => _reExport(entry),
                        icon: isExporting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.file_download_outlined, size: 18),
                        label: Text(isExporting ? 'Export...' : 'Re-exporter'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _delete(entry),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFFDC2626),
                      ),
                      tooltip: 'Supprimer',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final mo = date.month.toString().padLeft(2, '0');
    return '$d/$mo/${date.year} à $h:$m';
  }
}
