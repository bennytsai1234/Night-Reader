import 'dart:async';

/// AppEventBus - 全域事件總線
/// 負責 App 內部的通訊機制，(原 Android constant/EventBus.kt)
class AppEventBus {
  static final AppEventBus _instance = AppEventBus._internal();
  factory AppEventBus() => _instance;
  AppEventBus._internal();

  final StreamController<AppEvent> _controller =
      StreamController<AppEvent>.broadcast();

  /// 獲取所有事件流
  Stream<AppEvent> get stream => _controller.stream;

  /// 發送事件
  void fire(AppEvent event) {
    _controller.add(event);
  }

  /// 監聽特定類型的事件數據
  Stream<T> on<T>() {
    return stream
        .where((event) => event.data is T)
        .map((event) => event.data as T);
  }

  /// 監聽特定名稱的事件
  Stream<AppEvent> onName(String name) {
    return stream.where((event) => event.name == name);
  }

  // --- 常量事件名稱 (原 Android EventBus.kt) ---
  static const String mediaButton = 'mediaButton';
  static const String recreate = 'RECREATE';
  static const String upBookshelf = 'upBookToc';
  static const String bookshelfRefresh = 'bookshelfRefresh';
  static const String aloudState = 'aloud_state';
  static const String ttsProgress = 'ttsStart';
  static const String upConfig = 'upConfig';
  static const String webService = 'webService';
  static const String upDownload = 'upDownload';
  static const String upDownloadState = 'upDownloadState';
  static const String saveContent = 'saveContent';
  static const String checkSource = 'checkSource';
  static const String checkSourceDone = 'checkSourceDone';
  static const String sourceChanged = 'sourceChanged';
  static const String searchResult = 'searchResult';
  static const String updateReadActionBar = 'updateReadActionBar';
}

/// AppEvent - 事件封裝對象
class AppEvent {
  final String name;
  final dynamic data;

  AppEvent(this.name, {this.data});
}
