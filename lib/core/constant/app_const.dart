/// AppConst - 全域常數定義 (原 Android constant/AppConst.kt)
class AppConst {
  AppConst._();

  static const String appTag = 'YeDu';
  static const String uaName = 'User-Agent';
  static const int maxThread = 9;
  static const int defaultWebDavId = -1;
  static const String imagePathKey = 'imagePath';

  static const List<String> charsets = [
    'UTF-8',
    'GB2312',
    'GB18030',
    'GBK',
    'Unicode',
    'UTF-16',
    'UTF-16LE',
    'ASCII',
  ];

  // 章節背景下載通道
  static const String channelIdDownload = 'channel_download';
  static const String channelIdReadAloud = 'channel_read_aloud';
  static const String channelIdWeb = 'channel_web';

  // 時間格式 (對標 FastDateFormat)
  static const String timeFormat = 'HH:mm';
  static const String dateFormat = 'yyyy/MM/dd HH:mm';
  static const String fileNameFormat = 'yy-MM-dd-HH-mm-ss';
}

/// AppVariant - 應用程式版本變體 (原 Android help/update/AppVariant)
enum AppVariant {
  official,
  betaReleaseA,
  betaRelease,
  unknown;

  bool isBeta() {
    return this == betaRelease || this == betaReleaseA;
  }
}

/// AppInfo - 應用程式資訊
class AppInfo {
  final int versionCode;
  final String versionName;
  final AppVariant appVariant;

  AppInfo({
    this.versionCode = 0,
    this.versionName = '',
    this.appVariant = AppVariant.unknown,
  });
}

/// PlaybackStatus - 播放狀態 (原 Android constant/Status.kt)
class PlaybackStatus {
  PlaybackStatus._();
  static const int stop = 0;
  static const int play = 1;
  static const int pause = 3;
}
