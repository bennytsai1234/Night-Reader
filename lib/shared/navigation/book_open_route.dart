import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_open_target.dart';
import 'package:night_reader/features/reader_v2/shell/reader_v2_page.dart';

/// 開書轉場：短促的淡入 + 輕微上滑。
///
/// 刻意保持輕量——以 transform 為主（[SlideTransition] 只是位移，不需離屏
/// 合成），搭配一段短暫的淡入。目的地 [ReaderV2Page] 的重排版已由
/// `_openRuntimeAfterFirstFrame` 延後到第一幀後，因此轉場本身只需保持每幀
/// 便宜即可順暢，不再使用整頁 `Opacity`(saveLayer) 或 3D 透視 overlay。
class BookOpenRoute extends PageRouteBuilder {
  BookOpenRoute({
    required this.book,
    this.openTarget,
    this.initialChapters = const <BookChapter>[],
  }) : super(
         pageBuilder:
             (context, animation, secondaryAnimation) => ReaderV2Page(
               book: book,
               openTarget: openTarget,
               initialChapters: initialChapters,
             ),
         transitionDuration: const Duration(milliseconds: 280),
         reverseTransitionDuration: const Duration(milliseconds: 220),
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           final curved = CurvedAnimation(
             parent: animation,
             curve: Curves.easeOutCubic,
             reverseCurve: Curves.easeInCubic,
           );
           return FadeTransition(
             opacity: curved,
             child: SlideTransition(
               position: Tween<Offset>(
                 begin: const Offset(0, 0.04),
                 end: Offset.zero,
               ).animate(curved),
               child: child,
             ),
           );
         },
       );

  final Book book;
  final ReaderV2OpenTarget? openTarget;
  final List<BookChapter> initialChapters;
}
