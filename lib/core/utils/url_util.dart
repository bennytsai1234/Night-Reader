import 'package:path/path.dart' as p;

/// UrlUtil - URL 輔助工具 (原 Android utils/UrlUtil.kt)
class UrlUtil {
  UrlUtil._();

  static const List<String> unExpectFileSuffixs = ['php', 'html'];

  /// 替換 URL 中的保留字元
  static String replaceReservedChar(String text) {
    return text
        .replaceAll('%', '%25')
        .replaceAll(' ', '%20')
        .replaceAll('"', '%22')
        .replaceAll('#', '%23')
        .replaceAll('&', '%26')
        .replaceAll('(', '%28')
        .replaceAll(')', '%29')
        .replaceAll('+', '%2B')
        .replaceAll(',', '%2C')
        .replaceAll('/', '%2F')
        .replaceAll(':', '%3A')
        .replaceAll(';', '%3B')
        .replaceAll('<', '%3C')
        .replaceAll('=', '%3D')
        .replaceAll('>', '%3E')
        .replaceAll('?', '%3F')
        .replaceAll('@', '%40')
        .replaceAll('\\', '%5C')
        .replaceAll('|', '%7C');
  }

  /// 從路徑中獲取檔案名稱
  static String? getFileNameFromPath(Uri uri) {
    final path = uri.path;
    if (path.isEmpty) return null;
    final suffix = getSuffix(path, '');
    if (suffix != '' && !unExpectFileSuffixs.contains(suffix)) {
      return p.basename(path);
    }
    return null;
  }

  /// 從 Content-Disposition 獲取檔案名稱
  static String? getFileNameFromContentDisposition(String? disposition) {
    if (disposition == null) return null;
    final fileNames = disposition
        .split(RegExp(r';\s*'))
        .where((it) => it.contains('filename'));

    for (var it in fileNames) {
      var fileName = it.split('=')[1].trim();
      fileName = fileName
          .replaceAll(RegExp(r'^"'), '')
          .replaceAll(RegExp(r'"$'), '');

      if (it.contains('filename*')) {
        final data = fileName.split("''");
        if (data.length > 1) {
          try {
            return Uri.decodeComponent(data[1]);
          } catch (_) {
            return null;
          }
        }
      } else {
        return fileName;
      }
    }
    return null;
  }

  /// 獲取合法的文件字尾
  static String getSuffix(String str, [String? defaultValue]) {
    // 移除 URL 中的內容選項 (對標 CustomUrl)
    final url = str.split('?')[0].split('#')[0];
    var suffix = p.extension(url);
    if (suffix.startsWith('.')) {
      suffix = suffix.substring(1);
    }

    final fileSuffixRegex = RegExp(r'^[a-zA-Z0-9]+$');
    if (suffix.length > 5 || !fileSuffixRegex.hasMatch(suffix)) {
      return defaultValue ?? 'ext';
    }
    return suffix;
  }
}
