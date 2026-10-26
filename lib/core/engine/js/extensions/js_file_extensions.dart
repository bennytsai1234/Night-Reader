import 'dart:io';

import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/encoding_detect.dart';

import '../js_extensions_base.dart';
import 'js_blocking_tasks.dart';

/// JsExtensions 的文件 IO 與壓縮處理擴展。
///
/// 給了完整路徑的直接在這裡讀；要問平台暫存或文件資料夾在哪、要下載的，
/// 交給網路 isolate（[BlockingCall]，ADR 0034）。
extension JsFileExtensions on JsExtensionsBase {
  void injectFileExtensions() {
    // ─── java.downloadFile(url) — 返回本地路徑 ───────────────────
    onBlocking(
      'downloadFile',
      (url) => BlockingCall.run(downloadToTemp('$url')),
    );

    // ─── java.readFile(path) — 返回 byte array ───────────────────
    onBlocking('readFile', (path) {
      try {
        final file = File('$path');
        return file.existsSync() ? file.readAsBytesSync() : null;
      } catch (e) {
        AppLog.e('java.readFile failed: $e');
        return null;
      }
    });

    // ─── java.readTxtFile(path, charset) — 返回文字內容 ─────────
    onBlocking('readTxtFile', (payload) {
      final String path;
      final String charset;
      if (payload is List && payload.isNotEmpty) {
        path = payload[0].toString();
        charset = payload.length > 1 && payload[1] != null
            ? payload[1].toString()
            : 'UTF-8';
      } else {
        path = payload.toString();
        charset = 'UTF-8';
      }
      try {
        final file = File(path);
        if (!file.existsSync()) return '';
        return EncodingDetect.decodeWithCharset(
          file.readAsBytesSync(),
          charset,
        );
      } catch (e) {
        AppLog.e('java.readTxtFile failed: $e');
        return '';
      }
    });

    // ─── java.unArchiveFile(zipRelPath) — 解壓到 temp，返回 rel 路徑 ─
    onBlocking(
      'unArchiveFile',
      (relPath) => BlockingCall.run(unArchive('$relPath')),
    );

    // ─── java.getTxtInFolder(relPath) — 返回資料夾內所有 txt 串接 ───
    onBlocking(
      'getTxtInFolder',
      (relPath) => BlockingCall.run(textInTempFolder('$relPath')),
    );
  }
}
