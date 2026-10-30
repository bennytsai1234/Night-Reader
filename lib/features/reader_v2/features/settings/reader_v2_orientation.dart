import 'package:flutter/services.dart';

/// 閱讀器露在畫面上時的螢幕方向；離開閱讀器後恢復跟隨系統。
enum ReaderV2Orientation {
  system('跟隨系統', <DeviceOrientation>[]),
  portrait('直向', [DeviceOrientation.portraitUp]),
  landscape('橫向', [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  const ReaderV2Orientation(this.label, this.preferred);

  final String label;

  /// 交給 [SystemChrome.setPreferredOrientations] 的方向；空的是跟隨系統。
  final List<DeviceOrientation> preferred;

  static ReaderV2Orientation parse(String? name) => values.firstWhere(
    (orientation) => orientation.name == name,
    orElse: () => system,
  );
}
