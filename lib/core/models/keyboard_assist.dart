/// KeyboardAssist - 鍵盤輔助模型
/// (原 Android data/entities/KeyboardAssist.kt)
class KeyboardAssist {
  int type;
  String key;
  String value;
  int serialNo;

  KeyboardAssist({
    this.type = 0,
    required this.key,
    required this.value,
    this.serialNo = 0,
  });

  Map<String, dynamic> toJson() {
    return {'type': type, 'key': key, 'value': value, 'serialNo': serialNo};
  }

  factory KeyboardAssist.fromJson(Map<String, dynamic> json) {
    return KeyboardAssist(
      type: json['type'] ?? 0,
      key: json['key'] ?? '',
      value: json['value'] ?? '',
      serialNo: json['serialNo'] ?? 0,
    );
  }
}
