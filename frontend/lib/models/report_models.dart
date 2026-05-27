class InterpretRequest {
  InterpretRequest({
    required this.site,
    required this.contrat,
    required this.zone,
    required this.description,
  });

  final String site;
  final String contrat;
  final String zone;
  final String description;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'site': site,
      'contrat': contrat,
      'zone': zone,
      'description': description,
    };
  }
}

class EquipmentRow {
  EquipmentRow({
    required this.site,
    required this.contrat,
    required this.zone,
    required this.equipement,
    required this.description,
  });

  final String site;
  final String contrat;
  final String zone;
  final String equipement;
  final String description;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'site': site,
      'contrat': contrat,
      'zone': zone,
      'equipement': equipement,
      'description': description,
    };
  }

  factory EquipmentRow.fromJson(Map<String, dynamic> json) {
    return EquipmentRow(
      site: json['site'] as String? ?? '',
      contrat: json['contrat'] as String? ?? '',
      zone: json['zone'] as String? ?? '',
      equipement: json['equipement'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}

class InterpretResponse {
  InterpretResponse({
    required this.rows,
    required this.rawModelOutput,
  });

  final List<EquipmentRow> rows;
  final String rawModelOutput;

  factory InterpretResponse.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'] as List<dynamic>? ?? <dynamic>[];
    return InterpretResponse(
      rows: rawRows
          .map((item) => EquipmentRow.fromJson(item as Map<String, dynamic>))
          .toList(),
      rawModelOutput: json['raw_model_output'] as String? ?? '',
    );
  }
}
