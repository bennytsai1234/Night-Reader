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
  final int startChapterIndex;
  final int endChapterIndex;
  int currentChapterIndex;
  int status; // 0: 等待中, 1: 下載中, 2: 已暫停, 3: 已完成, 4: 失敗
  int totalCount;
  int successCount;
  int errorCount;
  int lastUpdateTime;
  String? lastErrorReason;
  String? lastErrorMessage;
  int? lastErrorChapterIndex;

  DownloadTask({
    required this.bookUrl,
    required this.bookName,
    required this.startChapterIndex,
    required this.endChapterIndex,
    this.currentChapterIndex = 0,
    this.status = 0,
    this.totalCount = 0,
    this.successCount = 0,
    this.errorCount = 0,
    this.lastUpdateTime = 0,
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
    final chapter =
        lastErrorChapterIndex == null
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
      startChapterIndex: json['startChapterIndex'],
      endChapterIndex: json['endChapterIndex'],
      currentChapterIndex: json['currentChapterIndex'] ?? 0,
      status: json['status'] ?? 0,
      totalCount: json['totalCount'] ?? 0,
      successCount: json['successCount'] ?? 0,
      errorCount: json['errorCount'] ?? 0,
      lastUpdateTime: json['lastUpdateTime'] ?? 0,
      lastErrorReason: json['lastErrorReason'],
      lastErrorMessage: json['lastErrorMessage'],
      lastErrorChapterIndex: json['lastErrorChapterIndex'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bookUrl': bookUrl,
      'bookName': bookName,
      'startChapterIndex': startChapterIndex,
      'endChapterIndex': endChapterIndex,
      'currentChapterIndex': currentChapterIndex,
      'status': status,
      'totalCount': totalCount,
      'successCount': successCount,
      'errorCount': errorCount,
      'lastUpdateTime': lastUpdateTime,
      'lastErrorReason': lastErrorReason,
      'lastErrorMessage': lastErrorMessage,
      'lastErrorChapterIndex': lastErrorChapterIndex,
    };
  }

  DownloadTask copyWith({
    String? bookUrl,
    String? bookName,
    int? startChapterIndex,
    int? endChapterIndex,
    int? currentChapterIndex,
    int? status,
    int? totalCount,
    int? successCount,
    int? errorCount,
    int? lastUpdateTime,
    String? lastErrorReason,
    String? lastErrorMessage,
    int? lastErrorChapterIndex,
  }) {
    return DownloadTask(
      bookUrl: bookUrl ?? this.bookUrl,
      bookName: bookName ?? this.bookName,
      startChapterIndex: startChapterIndex ?? this.startChapterIndex,
      endChapterIndex: endChapterIndex ?? this.endChapterIndex,
      currentChapterIndex: currentChapterIndex ?? this.currentChapterIndex,
      status: status ?? this.status,
      totalCount: totalCount ?? this.totalCount,
      successCount: successCount ?? this.successCount,
      errorCount: errorCount ?? this.errorCount,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      lastErrorReason: lastErrorReason ?? this.lastErrorReason,
      lastErrorMessage: lastErrorMessage ?? this.lastErrorMessage,
      lastErrorChapterIndex:
          lastErrorChapterIndex ?? this.lastErrorChapterIndex,
    );
  }
}
