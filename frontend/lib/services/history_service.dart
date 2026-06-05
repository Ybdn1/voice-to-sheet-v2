import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_models.dart';

/// Persiste la liste des relevés exportés (max 50 entrées).
class HistoryService {
  static const String _key = 'report_history_v1';
  static const int _maxEntries = 50;

  Future<List<HistoryEntry>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return <HistoryEntry>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <HistoryEntry>[];
    }
  }

  Future<void> addEntry(HistoryEntry entry) async {
    final entries = await loadHistory();
    entries.insert(0, entry);
    final capped = entries.take(_maxEntries).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(capped.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> deleteEntry(String id) async {
    final entries = await loadHistory();
    entries.removeWhere((e) => e.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
