import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Données du formulaire sauvegardées localement entre deux sessions.
class FormDraft {
  const FormDraft({
    this.siteId,
    this.contractId,
    this.zoneId,
    required this.description,
  });

  final String? siteId;
  final String? contractId;
  final String? zoneId;
  final String description;

  /// Vrai si le brouillon ne contient aucune donnée utile.
  bool get isEmpty => description.isEmpty && siteId == null;

  factory FormDraft.fromJson(Map<String, dynamic> json) => FormDraft(
        siteId: json['siteId'] as String?,
        contractId: json['contractId'] as String?,
        zoneId: json['zoneId'] as String?,
        description: json['description'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (siteId != null) 'siteId': siteId,
        if (contractId != null) 'contractId': contractId,
        if (zoneId != null) 'zoneId': zoneId,
        'description': description,
      };
}

/// Persiste et restaure le brouillon du formulaire via SharedPreferences.
class DraftService {
  static const String _key = 'form_draft_v1';

  Future<FormDraft?> loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return FormDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDraft(FormDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(draft.toJson()));
  }

  Future<void> clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
