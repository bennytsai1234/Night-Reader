import 'dart:async';

import 'package:event_bus/event_bus.dart';

class AppEventBus {
  static final AppEventBus _instance = AppEventBus._internal();
  factory AppEventBus() => _instance;
  AppEventBus._internal();

  final EventBus _eventBus = EventBus();

  // Event Names
  static const String upBookshelf = 'upBookshelf';
  static const String mediaButton = 'mediaButton';
  static const String recreate = 'RECREATE';
  static const String aloudState = 'aloud_state';
  static const String ttsProgress = 'ttsStart';
  static const String upConfig = 'upConfig';
  static const String webService = 'webService';
  static const String upDownload = 'upDownload';
  static const String upDownloadState = 'upDownloadState';
  static const String saveContent = 'saveContent';
  static const String searchResult = 'searchResult';
  static const String updateReadActionBar = 'updateReadActionBar';

  /// 書籍詳情讀到或存好封面；data 是 [BookCoverEvent]。
  static const String bookCover = 'bookCover';

  /// 一本書換了書源（網址可能也換了，舊的那筆已刪掉）；data 是
  /// [BookSwitchedEvent]。
  static const String bookSwitched = 'bookSwitched';

  /// 書源換了網址（編輯、AI 修復與還原、修復異常書源、同步搬書源、合併
  /// 重複書源）；data 是 [SourceMovedEvent]。發的時候資料庫裡的書、正文與
  /// 書本資料夾都已經搬到新網址，開著這些書的頁面與播放器照它換上新書源。
  static const String sourceMoved = 'sourceMoved';

  /// 使用者或同步刪掉了書源（[BookSourceDao.deleteByUrls]；併掉重複的、
  /// 改網址不算，書跟著搬走了）；data 是刪掉的網址 `List<String>`。用它的
  /// 書架上的書自動換源（ADR 0069）。
  static const String sourcesDeleted = 'sourcesDeleted';

  void fire(String name, {dynamic data}) {
    _eventBus.fire(AppEvent(name, data: data));
  }

  Stream<AppEvent> on() {
    return _eventBus.on<AppEvent>();
  }

  Stream<AppEvent> onName(String name) {
    return _eventBus.on<AppEvent>().where((event) => event.name == name);
  }
}

class AppEvent {
  final String name;
  final dynamic data;

  AppEvent(this.name, {this.data});
}

/// 書籍詳情顯示的封面（可能是詳情頁才有的網址，或已存到手機的檔案）。
/// 搜尋結果多半沒有這個封面，收到後讓同一本書的卡片沿用。
class BookCoverEvent {
  final String bookUrl;
  final String cover;

  const BookCoverEvent({required this.bookUrl, required this.cover});
}

/// 換源前後這本書的網址；兩者可能相同（只換了書源）。
class BookSwitchedEvent {
  final String fromBookUrl;
  final String toBookUrl;

  const BookSwitchedEvent({required this.fromBookUrl, required this.toBookUrl});
}

/// 書源從 [fromUrl] 搬到 [toUrl]（[AppEventBus.sourceMoved]）。
class SourceMovedEvent {
  final String fromUrl;
  final String toUrl;

  const SourceMovedEvent({required this.fromUrl, required this.toUrl});
}
