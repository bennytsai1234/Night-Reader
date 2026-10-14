import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_open_target.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_read_time_scope.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page.dart';

/// 開閱讀器。轉場與其他換頁相同（「外觀與主題 → 換頁動畫」）；目的地
/// [ReaderV2Page] 的重排版延後到第一幀後，轉場本身每幀都便宜。
///
/// 閱讀器維持不能從左緣右滑返回（原本自帶轉場時就沒有），由選單或返回鍵離開。
class BookOpenRoute extends MaterialPageRoute<void> {
  BookOpenRoute({
    required this.book,
    this.openTarget,
    this.initialChapters = const <BookChapter>[],
  }) : super(
         builder: (context) => ReaderV2ReadTimeScope(
           book: book,
           child: ReaderV2Page(
             book: book,
             openTarget: openTarget,
             initialChapters: initialChapters,
           ),
         ),
       );

  final Book book;
  final ReaderV2OpenTarget? openTarget;
  final List<BookChapter> initialChapters;

  @override
  bool get popGestureEnabled => false;
}
