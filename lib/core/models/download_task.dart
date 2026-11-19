/// DownloadTask - 下載任務模型
/// 用於持久化儲存下載隊列，確保 App 重啟後能恢復
class DownloadTask {
  static const int statusWaiting = 0;
  static const int statusDownloading = 1;
  static const int statusPaused = 2;
  static const int statusCompleted = 3;
  static const int statusFailed = 4;

  final String bookUrl;
  final String bookName;

  /// 要下載的範圍，起訖用章節網址記：書源在中間插章或刪章時序號會位移，
  /// 網址不會（ADR 0008）。null 表示從第一章／到目錄最後一章，整本的任務
  /// 兩端都是 null。開始下載時才對照當下的目錄換算成章節。
  final String? startChapterUrl;
  final String? endChapterUrl;
  int currentChapterIndex;
  int status; // 0: 等待中, 1: 下載中, 2: 已暫停, 3: 已完成, 4: 失敗
  int totalCount;
  int successCount;
  int errorCount;
  int lastUpdateTime;

  /// 佇列中的順序（小的先下載）；上移／下移時寫回，重開 App 後保留。
  int sortOrder;
  String? lastErrorReason;
  String? lastErrorMessage;
  int? lastErrorChapterIndex;

  DownloadTask({
    required this.bookUrl,
    required this.bookName,
    this.startChapterUrl,
    this.endChapterUrl,
    this.currentChapterIndex = 0,
    this.status = 0,
    this.totalCount = 0,
    this.successCount = 0,
    this.errorCount = 0,
    this.lastUpdateTime = 0,
    this.sortOrder = 0,
    this.lastErrorReason,
    this.lastErrorMessage,
    this.lastErrorChapterIndex,
  });

  bool get isWaiting => status == statusWaiting;
  bool get isDownloading => status == statusDownloading;
  bool get isPaused => status == statusPaused;
  bool get isCompleted => status == statusCompleted;
  bool get isFailed => status == statusFailed;
  bool get hasFailures => errorCount > 0 || isFailed;

  /// 可以重試：失敗了，或跑完但有章節失敗。下載中、排隊中的不行（那一輪
  /// 還在跑，歸零計數會把失敗的章節當成完成）。
  bool get canRetry =>
      isFailed || (errorCount > 0 && !isDownloading && !isWaiting);

  /// 下載佇列那一列的紅字：哪一章（[unit] 是這本書的單位：章、話、集）與
  /// 原因，例如「第 3 章：連不上網站，檢查網路後重試或換源」
  /// （`DownloadFailure`）。原因那句已經說了發生什麼，失敗類型
  /// （[lastErrorReason]）只在「查看失敗原因」裡寫。沒有記錄原因時為 null。
  String? failureSummary({String unit = '章'}) {
    final message = lastErrorMessage ?? '';
    if (message.isEmpty) return null;
    return switch (lastErrorChapterIndex) {
      final index? => '第 ${index + 1} $unit：$message',
      null => message,
    };
  }

  void setFailure({
    required String reason,
    required String message,
    int? chapterIndex,
  }) {
    lastErrorReason = reason;
    lastErrorMessage = message;
    lastErrorChapterIndex = chapterIndex;
  }

  void clearFailure() {
    lastErrorReason = null;
    lastErrorMessage = null;
    lastErrorChapterIndex = null;
  }

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      bookUrl: json['bookUrl'],
      bookName: json['bookName'],
      // 舊版備份只有序號範圍，沒有網址：還原成整本。
      startChapterUrl: json['startChapterUrl'],
      endChapterUrl: json['endChapterUrl'],
      currentChapterIndex: json['currentChapterIndex'] ?? 0,
      status: json['status'] ?? 0,
      totalCount: json['totalCount'] ?? 0,
      successCount: json['successCount'] ?? 0,
      errorCount: json['errorCount'] ?? 0,
      lastUpdateTime: json['lastUpdateTime'] ?? 0,
      sortOrder: json['sortOrder'] ?? 0,
      lastErrorReason: json['lastErrorReason'],
      lastErrorMessage: json['lastErrorMessage'],
      lastErrorChapterIndex: json['lastErrorChapterIndex'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bookUrl': bookUrl,
      'bookName': bookName,
      'startChapterUrl': startChapterUrl,
      'endChapterUrl': endChapterUrl,
      'currentChapterIndex': currentChapterIndex,
      'status': status,
      'totalCount': totalCount,
      'successCount': successCount,
      'errorCount': errorCount,
      'lastUpdateTime': lastUpdateTime,
      'sortOrder': sortOrder,
      'lastErrorReason': lastErrorReason,
      'lastErrorMessage': lastErrorMessage,
      'lastErrorChapterIndex': lastErrorChapterIndex,
    };
  }
}
