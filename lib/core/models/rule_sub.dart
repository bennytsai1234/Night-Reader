/// RuleSub - 規則訂閱模型
/// (原 Android data/entities/RuleSub.kt)
class RuleSub {
  int id;
  String name;
  String url;
  int type;
  bool enabled;
  int order;

  RuleSub({
    this.id = 0,
    this.name = '',
    this.url = '',
    this.type = 0,
    this.enabled = true,
    this.order = 0,
  });

  factory RuleSub.fromJson(Map<String, dynamic> json) {
    return RuleSub(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch,
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      type: json['type'] ?? 0,
      enabled: json['enabled'] == 1 || json['enabled'] == true,
      order: json['customOrder'] ?? json['order'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'type': type,
      'enabled': enabled ? 1 : 0,
      'order': order,
    };
  }
}
