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

  String? get failureSummary {
    if (!hasFailures && (lastErrorMessage ?? '').isEmpty) return null;
    final reason = lastErrorReason ?? '下載失敗';
    final chapter = lastErrorChapterIndex == null
        ? ''
        : '，第 ${lastErrorChapterIndex! + 1} 章';
    final message = lastErrorMessage;
    if (message == null || message.isEmpty) {
      return '$reason$chapter';
    }
    return '$reason$chapter：$message';
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
