import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:share_plus/share_plus.dart';

/// 把匯出的 JSON 存成檔案、用系統分享傳出去（同 Legado 的分享）：書源與
/// 替換規則的「分享選中」。[fileName] 是檔名（`.json`、`.legado` 結尾會換成
/// `.json`），空的或不能當檔名時用 [fallbackName]；分享的說明寫「分享夜讀
/// [what] (檔名)」。
Future<void> shareJsonFile(
  String json, {
  required String fileName,
  required String fallbackName,
  required String what,
}) async {
  final baseName = _exportBaseName(fileName, fallbackName);
  final file = await AppStoragePaths.shareExportFile('$baseName.json');
  await file.writeAsString(json);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], text: '分享夜讀$what ($baseName.json)'),
  );
}

String _exportBaseName(String fileName, String fallbackName) {
  var baseName = fileName
      .replaceAll(RegExp(r'\.(legado|json)$', caseSensitive: false), '')
      .trim()
      .replaceAll(RegExp(r'[\x00-\x1F\x7F\\/:*?"<>|]'), '_')
      .trim();
  if (baseName.isEmpty || baseName == '.' || baseName == '..') {
    baseName = fallbackName;
  }
  return baseName;
}
