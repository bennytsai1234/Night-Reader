import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/features/audiobook/audiobook_page.dart';
import 'package:night_reader/features/comic_reader/comic_reader_page.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_open_target.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_read_time_scope.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page.dart';

/// 開書：漫畫進漫畫閱讀器（[ComicReaderPage]，ADR 0052），有聲書進播放器
/// （[AudiobookPage]，ADR 0055），其他進 [ReaderV2Page]。轉場與其他換頁相同
/// （「外觀與主題 → 換頁動畫」）；[ReaderV2Page] 的重排版延後到第一幀後，
/// 轉場本身每幀都便宜。
///
/// 兩種閱讀器的閱讀時間記進閱讀統計；收聽時間由播放器自己記（只算真的出聲
/// 的時間），不包閱讀時間。閱讀器維持不能從左緣右滑返回（原本自帶轉場時就
/// 沒有），由選單或返回鍵離開；播放器是一般的頁面，可以右滑返回。
class BookOpenRoute extends MaterialPageRoute<void> {
  BookOpenRoute({
    required this.book,
    this.openTarget,
    this.initialChapters = const <BookChapter>[],
  }) : super(
         builder: (context) {
           final startChapter =
               openTarget?.intent == ReaderV2OpenIntent.chapterStart
               ? openTarget!.location.chapterIndex
               : null;
           return switch (book.bookKind) {
             BookSourceKind.audio => AudiobookPage(
               book: book,
               chapterIndex: startChapter,
             ),
             BookSourceKind.comic => ReaderV2ReadTimeScope(
               book: book,
               child: ComicReaderPage(
                 book: book,
                 startChapter: startChapter,
                 initialChapters: initialChapters,
               ),
             ),
             _ => ReaderV2ReadTimeScope(
               book: book,
               child: ReaderV2Page(
                 book: book,
                 openTarget: openTarget,
                 initialChapters: initialChapters,
               ),
             ),
           };
         },
       );

  final Book book;
  final ReaderV2OpenTarget? openTarget;
  final List<BookChapter> initialChapters;

  @override
  bool get popGestureEnabled => book.bookKind == BookSourceKind.audio;
}
