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
  static const String sourceChanged = 'sourceChanged';
  static const String searchResult = 'searchResult';
  static const String updateReadActionBar = 'updateReadActionBar';

  /// 書籍詳情讀到或存好封面；data 是 [BookCoverEvent]。
  static const String bookCover = 'bookCover';

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
