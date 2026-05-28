/// Server - 伺服器模型
/// (原 Android data/entities/Server.kt)
class Server {
  int id;
  String name;
  String type;
  String? config;
  int sortNumber;

  Server({
    required this.id,
    this.name = '',
    this.type = 'NONE',
    this.config,
    this.sortNumber = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'config': config,
      'sortNumber': sortNumber,
    };
  }

  factory Server.fromJson(Map<String, dynamic> json) {
    return Server(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      type: json['type'] ?? 'NONE',
      config: json['config'],
      sortNumber: json['sortNumber'] ?? 0,
    );
  }
}
