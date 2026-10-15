/// 閱讀器亮度：亮度條上的一個位置（0–1）換算成背光與加暗。
///
/// [dimZone] 以上調視窗背光（不改系統設定）；以下是加暗段：背光維持最低，
/// 正文再疊一層黑色，讓手機最暗時還能更暗。
abstract final class ReaderV2Brightness {
  /// 亮度條下方這一段是加暗段。四分之一讓背光段仍有大半條可以細調。
  static const double dimZone = 0.25;

  /// 拉到底時疊上的黑色不透明度。再暗下去，深色風格的正文就分不出字了。
  static const double maxDim = 0.6;

  /// 背光最低值。0 是 Android 的 `BRIGHTNESS_OVERRIDE_OFF`，有些機型會把
  /// 背光整個關掉，所以留一點。
  static const double minBacklight = 0.01;

  /// 第一次手動調整前的位置：背光段的中間偏上。
  static const double defaultLevel = 0.6;

  static double normalize(double? level) {
    if (level == null || !level.isFinite) return defaultLevel;
    return level.clamp(0.0, 1.0).toDouble();
  }

  /// [level] 對應的視窗背光（0–1）。
  static double backlightFor(double level) {
    final value = normalize(level);
    if (value <= dimZone) return minBacklight;
    final ratio = (value - dimZone) / (1 - dimZone);
    return minBacklight + ratio * (1 - minBacklight);
  }

  /// [level] 對應疊在正文上的黑色不透明度；背光段為 0。
  static double dimFor(double level) {
    final value = normalize(level);
    if (value >= dimZone) return 0;
    return (dimZone - value) / dimZone * maxDim;
  }
}
