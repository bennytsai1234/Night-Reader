import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'dart:convert';
import 'package:night_reader/core/services/app_log_service.dart';
import '../js_extensions_base.dart';
import '../js_encode_utils.dart';
import 'package:night_reader/core/services/http_client.dart';
import 'package:night_reader/core/services/encoding_detect.dart';

/// JsExtensions 的文件 IO 與壓縮處理擴展
///
/// 所有 handler 都走 Promise bridge：收到 `[id, payload]`，
/// 啟動 async 工作後以 [JsExtensionsBase.resolveJsPending] 回 resolve JS Promise。
extension JsFileExtensions on JsExtensionsBase {
  void injectFileExtensions() {
    // ─── java.downloadFile(url) — 返回本地路徑 ───────────────────
    runtime.onMessage('downloadFile', (dynamic args) {
      final parsed = JsExtensionsBase.parseAsyncCallArgs(args);
      final url = parsed.payload.toString();
      () async {
        try {
          final key = JsEncodeUtils.md5Encode16(url);
          final tempDir = await getTemporaryDirectory();
          final savePath = p.join(tempDir.path, 'downloads', key);
          final file = File(savePath);
          if (!await file.parent.exists()) {
            await file.parent.create(recursive: true);
          }
          await HttpClient().client.download(url, savePath);
          resolveJsPending(parsed.callId, savePath);
        } catch (e) {
          AppLog.e('java.downloadFile failed: $e');
          resolveJsPending(parsed.callId, '');
        }
      }();
      return null;
    });

    // ─── java.readFile(path) — 返回 byte array (List<int>) ──────
    runtime.onMessage('readFile', (dynamic args) {
      final parsed = JsExtensionsBase.parseAsyncCallArgs(args);
      final path = parsed.payload.toString();
      () async {
        try {
          final file = File(path);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            resolveJsPending(parsed.callId, bytes);
          } else {
            resolveJsPending(parsed.callId, null);
          }
        } catch (e) {
          AppLog.e('java.readFile failed: $e');
          resolveJsPending(parsed.callId, null);
        }
      }();
      return null;
    });

    // ─── java.readTxtFile(path, charset) — 返回文字內容 ─────────
    runtime.onMessage('readTxtFile', (dynamic args) {
      final parsed = JsExtensionsBase.parseAsyncCallArgs(args);
      final payload = parsed.payload;
      final String path;
      final String charset;
      if (payload is List && payload.isNotEmpty) {
        path = payload[0].toString();
        charset = payload.length > 1 ? payload[1].toString() : 'UTF-8';
      } else {
        path = payload.toString();
        charset = 'UTF-8';
      }
      () async {
        try {
          final file = File(path);
          if (!await file.exists()) {
            resolveJsPending(parsed.callId, '');
            return;
          }
          final bytes = await file.readAsBytes();
          final cs = charset.toUpperCase();
          final content =
              (cs.contains('GBK') || cs.contains('GB2312'))
                  ? gbk.decode(bytes)
                  : utf8.decode(bytes, allowMalformed: true);
          resolveJsPending(parsed.callId, content);
        } catch (e) {
          AppLog.e('java.readTxtFile failed: $e');
          resolveJsPending(parsed.callId, '');
        }
      }();
      return null;
    });

    // ─── java.unArchiveFile(zipRelPath) — 解壓到 temp，返回 rel 路徑 ─
    runtime.onMessage('unArchiveFile', (dynamic args) {
      final parsed = JsExtensionsBase.parseAsyncCallArgs(args);
      final relPath = parsed.payload.toString();
      () async {
        try {
          final docs = await getApplicationDocumentsDirectory();
          final file = File(p.join(docs.path, relPath));
          if (!await file.exists()) {
            resolveJsPending(parsed.callId, '');
            return;
          }
          final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
          final tempDir = await getTemporaryDirectory();
          final outPath = p.join(
            tempDir.path,
            'ArchiveTemp',
            JsEncodeUtils.md5Encode16(file.path),
          );
          for (final entry in archive) {
            if (entry.isFile) {
              final data = entry.content as List<int>;
              File(p.join(outPath, entry.name))
                ..createSync(recursive: true)
                ..writeAsBytesSync(data);
            }
          }
          resolveJsPending(
            parsed.callId,
            p.relative(outPath, from: tempDir.path),
          );
        } catch (e) {
          AppLog.e('java.unArchiveFile failed: $e');
          resolveJsPending(parsed.callId, '');
        }
      }();
      return null;
    });

    // ─── java.getTxtInFolder(relPath) — 返回資料夾內所有 txt 串接 ───
    runtime.onMessage('getTxtInFolder', (dynamic args) {
      final parsed = JsExtensionsBase.parseAsyncCallArgs(args);
      final relPath = parsed.payload.toString();
      () async {
        try {
          final tempDir = await getTemporaryDirectory();
          final folder = Directory(p.join(tempDir.path, relPath));
          if (!await folder.exists()) {
            resolveJsPending(parsed.callId, '');
            return;
          }
          final buffer = StringBuffer();
          final files = folder.listSync().whereType<File>().toList();
          for (final f in files) {
            final bytes = await f.readAsBytes();
            final content =
                EncodingDetect.getEncode(bytes) == 'GBK'
                    ? gbk.decode(bytes)
                    : utf8.decode(bytes, allowMalformed: true);
            buffer.writeln(content);
          }
          resolveJsPending(parsed.callId, buffer.toString());
        } catch (e) {
          AppLog.e('java.getTxtInFolder failed: $e');
          resolveJsPending(parsed.callId, '');
        }
      }();
      return null;
    });
  }
}
