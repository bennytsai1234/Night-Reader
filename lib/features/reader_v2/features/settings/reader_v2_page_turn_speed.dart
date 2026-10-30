/// 點擊、音量鍵與選單翻頁時捲過一屏要多久。
enum ReaderV2PageTurnSpeed {
  fast('快', Duration(milliseconds: 160)),
  normal('標準', Duration(milliseconds: 260)),
  slow('慢', Duration(milliseconds: 400));

  const ReaderV2PageTurnSpeed(this.label, this.duration);

  final String label;
  final Duration duration;

  static ReaderV2PageTurnSpeed parse(String? name) =>
      values.firstWhere((speed) => speed.name == name, orElse: () => normal);
}
