import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// 選本地漫畫的作品資料夾（ADR 0052）。App 沒有儲存權限，Android 用系統的
/// 資料夾授權選，原生那邊（`ComicFolderCopy.kt`）把裡面的漫畫檔複製到
/// [dest] 底下，傳回複製好的資料夾；其他平台的選資料夾畫面給得出能讀的
/// 路徑，直接傳回它（之後匯入時再複製進 App）。取消時是 null。
abstract final class ComicFolderPicker {
  static const MethodChannel _channel = MethodChannel(
    'night_reader/comic_folder',
  );

  static Future<String?> pick({
    required String dest,
    void Function(int done, int total)? onProgress,
  }) async {
    if (!Platform.isAndroid) return FilePicker.getDirectoryPath();
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'progress') return;
      final args = call.arguments as Map<Object?, Object?>;
      onProgress?.call(args['done']! as int, args['total']! as int);
    });
    try {
      return await _channel.invokeMethod<String>('pickAndCopy', {'dest': dest});
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }
}
