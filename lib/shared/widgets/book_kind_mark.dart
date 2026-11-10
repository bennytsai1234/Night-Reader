import 'package:flutter/material.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';

/// 漫畫、有聲書的記號（ADR 0053）：同名的小說、漫畫、有聲是不同的書，搜尋
/// 結果卡在封面左下角放這個記號分出來（docs/design/screens.md「搜尋」）。
/// 小說不放。
class BookKindMark extends StatelessWidget {
  const BookKindMark(this.kind, {super.key});

  final BookSourceKind kind;

  /// 這一類的圖示；小說與不支援的沒有。
  static IconData? iconOf(BookSourceKind kind) => switch (kind) {
    BookSourceKind.comic => Icons.auto_stories_outlined,
    BookSourceKind.audio => Icons.headphones_outlined,
    BookSourceKind.novel || BookSourceKind.unsupported => null,
  };

  /// 切換類別的按鈕與選單用的圖示（發現頁的書源類型、搜尋頁的類別）：
  /// 小說是文字頁，漫畫、有聲同 [iconOf]。
  static IconData switchIconOf(BookSourceKind kind) =>
      iconOf(kind) ?? Icons.article_outlined;

  /// 給讀螢幕的人：「漫畫」「有聲書」。
  static String? labelOf(BookSourceKind kind) => switch (kind) {
    BookSourceKind.comic => '漫畫',
    BookSourceKind.audio => '有聲書',
    BookSourceKind.novel || BookSourceKind.unsupported => null,
  };

  /// [cover] 左下角疊上記號；小說原樣傳回。
  static Widget onCover(BookSourceKind kind, Widget cover) {
    if (iconOf(kind) == null) return cover;
    return Stack(
      children: [
        cover,
        Positioned(left: 3, bottom: 3, child: BookKindMark(kind)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final icon = iconOf(kind);
    if (icon == null) return const SizedBox.shrink();
    // 疊在封面上，封面深淺不定：淺色、深色都是半透明黑底白圖示。
    return Semantics(
      label: labelOf(kind),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(icon, size: 13, color: Colors.white),
      ),
    );
  }
}
