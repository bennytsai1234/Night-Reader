/// AppPattern - 全域正則定義 (原 Android constant/AppPattern.kt)
class AppPattern {
  static final RegExp jsPattern = RegExp(
    r'<js>([\w\W]*?)</js>|@js:([\w\W]*)',
    caseSensitive: false,
  );
  static final RegExp expPattern = RegExp(r'\{\{([\w\W]*?)\}\}');

  // 匹配格式化後的圖片格式
  static final RegExp imgPattern = RegExp(
    r'<img[^>]*src=["'
    "'"
    r']([^"'
    "'"
    r']*(?:["'
    "'"
    r'][^>]+\})?)["'
    "'"
    r'][^>]*>',
  );

  // dataURL 圖片類型
  static final RegExp dataUriRegex = RegExp(r'^data:.*?;base64,(.*)');

  static final RegExp nameRegex = RegExp(r'\s+作\s*者.*|\s+\S+\s+著');
  static final RegExp authorRegex = RegExp(r'^\s*作\s*者[:：\s]+|\s+著');
  static final RegExp fileNameRegex = RegExp(r'[\\/:*?"<>|.]');
  static final RegExp fileNameRegex2 = RegExp(r'[\\/:*?"<>|]');
  static final RegExp splitGroupRegex = RegExp(r'[,;，；]');
  static final RegExp titleNumPattern = RegExp(r'(第)(.+?)(章)');

  // 書源調試信息中的各種符號
  static final RegExp debugMessageSymbolRegex = RegExp(r'[⇒◇┌└≡]');

  // 本地書籍支援類型
  static final RegExp bookFileRegex = RegExp(
    r'.*\.(txt|epub|umd|pdf|mobi|azw3|azw)',
    caseSensitive: false,
  );
  // 壓縮文件支援類型
  static final RegExp archiveFileRegex = RegExp(
    r'.*\.(zip|rar|7z)$',
    caseSensitive: false,
  );

  /// 所有標點
  static final RegExp bdRegex = RegExp(r'(\p{P})+', unicode: true);

  /// 換行
  static final RegExp rnRegex = RegExp(r'[\r\n]');

  /// 不發音段落判斷
  static final RegExp notReadAloudRegex = RegExp(
    r'^(\s|\p{C}|\p{P}|\p{Z}|\p{S})+$',
    unicode: true,
  );

  static final RegExp xmlContentTypeRegex = RegExp(
    r'(application|text)/\w*\+?xml.*',
  );

  static final RegExp semicolonRegex = RegExp(r';');

  static final RegExp equalsRegex = RegExp(r'=');

  static final RegExp spaceRegex = RegExp(r'\s+');

  static final RegExp regexCharRegex = RegExp(r'[{}()\[\].+*?^$\\|]');

  static final RegExp lfRegex = RegExp(r'\n');
}
