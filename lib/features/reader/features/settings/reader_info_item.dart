/// 頁首／頁尾資訊列每個欄位可顯示的內容。
///
/// [code] 是持久化值，不得重新編號；新增項目只能附加新碼。宣告順序就是
/// 選單裡的順序，可以和碼不同。
enum ReaderInfoItem {
  none(0, '不顯示'),
  time(1, '時間'),
  bookName(2, '書名'),
  chapterTitle(3, '章節名稱'),
  chapterIndex(4, '章節序號'),
  chapterProgress(5, '本章進度'),
  bookProgress(6, '全書進度'),
  battery(7, '電量'),
  batteryIcon(10, '電量（只有圖示）'),
  batteryWithIcon(8, '電量（含圖示）'),
  batteryInside(9, '電量（數字在電池裡）');

  const ReaderInfoItem(this.code, this.label);

  final int code;
  final String label;

  /// 四種電量的顯示：只有數字、只有電池、電池加數字、數字在電池裡。
  bool get isBattery =>
      this == battery ||
      this == batteryIcon ||
      this == batteryWithIcon ||
      this == batteryInside;

  static ReaderInfoItem fromCode(int? code) {
    for (final item in values) {
      if (item.code == code) return item;
    }
    return none;
  }
}

/// 一條資訊列的左右兩欄。
final class ReaderInfoSlots {
  const ReaderInfoSlots({required this.left, required this.right});

  final ReaderInfoItem left;
  final ReaderInfoItem right;

  bool get isEmpty =>
      left == ReaderInfoItem.none && right == ReaderInfoItem.none;

  ReaderInfoSlots copyWith({ReaderInfoItem? left, ReaderInfoItem? right}) {
    return ReaderInfoSlots(left: left ?? this.left, right: right ?? this.right);
  }

  String encode() => '${left.code},${right.code}';

  static ReaderInfoSlots? decode(String? stored) {
    final parts = stored?.split(',');
    if (parts == null || parts.length != 2) return null;
    return ReaderInfoSlots(
      left: ReaderInfoItem.fromCode(int.tryParse(parts[0].trim())),
      right: ReaderInfoItem.fromCode(int.tryParse(parts[1].trim())),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderInfoSlots && other.left == left && other.right == right;

  @override
  int get hashCode => Object.hash(left, right);
}
