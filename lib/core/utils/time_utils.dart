/// TimeUtils - 時間輔助工具 (原 Android utils/TimeUtils.kt)
class TimeUtils {
  TimeUtils._();

  /// 將毫秒轉為 "多久以前" 字串
  static String toTimeAgo(int timestamp) {
    final curTime = DateTime.now().millisecondsSinceEpoch;
    final diff = (curTime - timestamp).abs();
    final seconds = diff / 1000;
    final suffix = timestamp < curTime ? '前' : '後';

    String start;
    if (seconds < 60) {
      start = '${seconds.toInt()}秒';
    } else if (seconds < 3600) {
      start = '${(seconds / 60).toInt()}分鐘';
    } else if (seconds < 86400) {
      start = '${(seconds / 3600).toInt()}小時';
    } else if (seconds < 604800) {
      start = '${(seconds / 86400).toInt()}天';
    } else if (seconds < 2628000) {
      start = '${(seconds / 604800).toInt()}周';
    } else if (seconds < 31536000) {
      start = '${(seconds / 2628000).toInt()}月';
    } else {
      start = '${(seconds / 31536000).toInt()}年';
    }

    return '$start$suffix';
  }

  /// 將毫秒轉為時長字串 (00:00:00)
  static String toDurationTime(int ms) {
    final totalSeconds = ms ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }
}
