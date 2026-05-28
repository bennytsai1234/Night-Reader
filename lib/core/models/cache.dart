/// Cache - 緩存模型
/// (原 Android data/entities/Cache.kt)
class Cache {
  final String key;
  String? value;
  int deadline;

  Cache({required this.key, this.value, this.deadline = 0});

  Map<String, dynamic> toJson() {
    return {'key': key, 'value': value, 'deadline': deadline};
  }

  factory Cache.fromJson(Map<String, dynamic> json) {
    return Cache(
      key: json['key'] ?? '',
      value: json['value'],
      deadline: json['deadline'] ?? 0,
    );
  }
}
