import 'package:flutter/services.dart';

/// 電量與充電狀態。
final class ReaderV2Battery {
  const ReaderV2Battery({required this.percent, required this.charging});

  final int percent;
  final bool charging;
}

/// 閱讀頁需要、但 Flutter 沒有直接提供的 Android 裝置資訊。
///
/// 原生端在 `MainActivity`；非 Android 平台沒有對應的 handler，查詢回傳
/// null、電量串流不發出資料。
abstract final class ReaderV2DeviceChannel {
  static const MethodChannel _device = MethodChannel(
    'night_reader/reader_device',
  );
  static const EventChannel _battery = EventChannel('night_reader/battery');

  /// 畫面上緣被鏡頭挖孔或曲面邊緣佔掉的高度（邏輯像素）。
  ///
  /// 與狀態列是否顯示無關；取不到時回傳 null。
  static Future<double?> topCutoutExtent() async {
    try {
      return await _device.invokeMethod<double>('topCutoutExtent');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static ReaderV2Battery? _latestBattery;

  /// 最近一次收到的電量；新訂閱者先以它顯示，不必等下一次變化。
  static ReaderV2Battery? get latestBattery => _latestBattery;

  /// 所有訂閱者共用同一個原生訂閱；最後一個訂閱者取消時原生端停止監聽。
  static final Stream<ReaderV2Battery> battery = _battery
      .receiveBroadcastStream()
      .map((event) {
        final data = event as Map<Object?, Object?>;
        return _latestBattery = ReaderV2Battery(
          percent: data['percent']! as int,
          charging: data['charging']! as bool,
        );
      });
}
