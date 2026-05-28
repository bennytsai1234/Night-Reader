/// SourceSubscription - 書源訂閱模型
class SourceSubscription {
  String url;
  String name;
  int type; // 0: 書源, 1: RSS, 2: 替換規則
  bool enabled;
  int order;

  // Transient field (not persisted to DB)
  int lastUpdateTime = 0;

  SourceSubscription({
    this.url = '',
    this.name = '',
    this.type = 0,
    this.enabled = true,
    this.order = 0,
    this.lastUpdateTime = 0,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'name': name,
    'type': type,
    'enabled': enabled ? 1 : 0,
    'order': order,
  };

  factory SourceSubscription.fromJson(Map<String, dynamic> json) {
    return SourceSubscription(
      url: json['url'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? 0,
      enabled: json['enabled'] == 1 || json['enabled'] == true,
      order: json['customOrder'] ?? json['order'] ?? 0,
    );
  }
}
