/// 正文裡的一張插圖（ADR 0050）：夾在 [offset] 那個字之前，圖不算字。
///
/// [offset] 是 [ReaderV2Content.displayText] 裡的 UTF-16 位置；落在段落開頭
/// 時圖在那一段前面，落在段落中間時那一段從這裡切開、圖夾在中間，等於
/// 正文長度時圖在章末。
final class ReaderV2Illustration {
  const ReaderV2Illustration({
    required this.offset,
    required this.src,
    required this.path,
    required this.pixelWidth,
    required this.pixelHeight,
  }) : assert(offset >= 0),
       assert(pixelWidth > 0),
       assert(pixelHeight > 0);

  final int offset;

  /// 標記裡寫的網址（網路書）或 EPUB 裡的路徑。
  final String src;

  /// 這張圖在這本書資料夾裡的檔案。
  final String path;
  final int pixelWidth;
  final int pixelHeight;

  @override
  bool operator ==(Object other) =>
      other is ReaderV2Illustration &&
      other.offset == offset &&
      other.src == src &&
      other.path == path &&
      other.pixelWidth == pixelWidth &&
      other.pixelHeight == pixelHeight;

  @override
  int get hashCode => Object.hash(offset, src, path, pixelWidth, pixelHeight);
}
