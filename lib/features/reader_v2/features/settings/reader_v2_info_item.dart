/// 頁首／頁尾資訊列每個欄位可顯示的內容。
///
/// [code] 是持久化值，不得重新編號；新增項目只能附加新碼。
enum ReaderV2InfoItem {
  none(0, '不顯示'),
  time(1, '時間'),
  bookName(2, '書名'),
  chapterTitle(3, '章節名稱'),
  chapterIndex(4, '章節序號'),
  chapterProgress(5, '本章進度'),
  bookProgress(6, '全書進度'),
  battery(7, '電量'),
  batteryWithIcon(8, '電量（含圖示）');

  const ReaderV2InfoItem(this.code, this.label);

  final int code;
  final String label;

  static ReaderV2InfoItem fromCode(int? code) {
    for (final item in values) {
      if (item.code == code) return item;
    }
    return none;
  }
}

/// 一條資訊列的左右兩欄。
final class ReaderV2InfoSlots {
  const ReaderV2InfoSlots({required this.left, required this.right});

  final ReaderV2InfoItem left;
  final ReaderV2InfoItem right;

  bool get isEmpty =>
      left == ReaderV2InfoItem.none && right == ReaderV2InfoItem.none;

  ReaderV2InfoSlots copyWith({ReaderV2InfoItem? left, ReaderV2InfoItem? right}) {
    return ReaderV2InfoSlots(
      left: left ?? this.left,
      right: right ?? this.right,
    );
  }

  String encode() => '${left.code},${right.code}';

  static ReaderV2InfoSlots? decode(String? stored) {
    final parts = stored?.split(',');
    if (parts == null || parts.length != 2) return null;
    return ReaderV2InfoSlots(
      left: ReaderV2InfoItem.fromCode(int.tryParse(parts[0].trim())),
      right: ReaderV2InfoItem.fromCode(int.tryParse(parts[1].trim())),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderV2InfoSlots && other.left == left && other.right == right;

  @override
  int get hashCode => Object.hash(left, right);
}
