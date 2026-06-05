import 'report_models.dart';

/// Une entrée dans l'historique des relevés exportés.
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.date,
    required this.site,
    required this.contrat,
    required this.zone,
    required this.rows,
  });

  final String id;
  final DateTime date;
  final String site;
  final String contrat;
  final String zone;
  final List<EquipmentRow> rows;

  int get nbRows => rows.length;

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        site: json['site'] as String,
        contrat: json['contrat'] as String,
        zone: json['zone'] as String,
        rows: (json['rows'] as List<dynamic>)
            .map((r) => EquipmentRow.fromJson(r as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'date': date.toIso8601String(),
        'site': site,
        'contrat': contrat,
        'zone': zone,
        'rows': rows.map((r) => r.toJson()).toList(),
      };
}
