class ReferenceItem {
  ReferenceItem({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;

  factory ReferenceItem.fromJson(Map<String, dynamic> json) {
    return ReferenceItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }
}

class ZoneItem {
  ZoneItem({
    required this.id,
    required this.siteId,
    required this.contractId,
    required this.name,
  });

  final String id;
  final String siteId;
  final String contractId;
  final String name;

  factory ZoneItem.fromJson(Map<String, dynamic> json) {
    return ZoneItem(
      id: json['id'] as String? ?? '',
      siteId: json['site_id'] as String? ?? '',
      contractId: json['contract_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }
}
