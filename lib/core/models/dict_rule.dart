/// DictRule - 字典規則模型
/// (原 Android data/entities/DictRule.kt)
class DictRule {
  int id;
  String name;
  String urlRule;
  String showRule;
  bool enabled;
  int sortNumber;

  DictRule({
    this.id = 0,
    this.name = '',
    this.urlRule = '',
    this.showRule = '',
    this.enabled = true,
    this.sortNumber = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id == 0 ? null : id,
      'name': name,
      'urlRule': urlRule,
      'showRule': showRule,
      'enabled': enabled ? 1 : 0,
      'sortNumber': sortNumber,
    };
  }

  factory DictRule.fromJson(Map<String, dynamic> json) {
    return DictRule(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      urlRule: json['urlRule'] ?? '',
      showRule: json['showRule'] ?? '',
      enabled: (json['enabled'] == 1) || (json['enabled'] == true),
      sortNumber: json['sortNumber'] ?? 0,
    );
  }
}
