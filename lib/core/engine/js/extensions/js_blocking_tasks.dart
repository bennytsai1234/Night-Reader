import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/network/cancellation.dart';
import 'package:night_reader/core/network/interceptors/app_interceptor.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/backstage_webview.dart';
import 'package:night_reader/core/services/cache_manager.dart';
import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/encoding_detect.dart';
import 'package:night_reader/core/services/http_client.dart';
import 'package:path/path.dart' as p;
import 'package:night_reader/core/storage/app_storage_paths.dart';

import '../js_encode_utils.dart';

/// 規則 JS 要等的呼叫交給網路 isolate 做的事（[BlockingCall]，ADR 0034）。
/// 工作連同捕捉的變數會送到網路 isolate，所以都在這裡的頂層函式建立，只
/// 捕捉網址、書源與字串這類資料（`CODING_STANDARDS.md` 背景執行）。網路
/// isolate 不跑規則 JS：網址裡的 JS 在書源 isolate 組 [AnalyzeUrl] 時就跑完了。
typedef BlockingTask = Future<Object?> Function();

/// 快取裡的 [key]（資料庫與檔案）。
BlockingTask cacheRead(String key) =>
    () => CacheManager().get(key);

/// [url] 的站點 Cookie（資料庫）。
BlockingTask cookieRead(String url) =>
    () => CookieStore().getCookie(url);

/// 回應的內文。
BlockingTask responseBody(AnalyzeUrl url) =>
    () async => (await url.getStrResponse()).body;

/// 同時抓，照 [urls] 的順序傳回內文。
BlockingTask responseBodies(List<AnalyzeUrl> urls) =>
    () async => [
      for (final response in await Future.wait(
        urls.map((u) => u.getStrResponse()),
      ))
        response.body,
    ];

/// `java.connect` 的回應：內文、網址、狀態與標頭。失敗時傳回 500 與錯誤
/// 訊息，不丟出，和原本一樣。
BlockingTask connectResponse(AnalyzeUrl url) => () async {
  try {
    final response = await url.getStrResponse();
    return {
      'body': response.body,
      'url': response.url,
      'requestUrl': url.url,
      'code': response.raw.statusCode ?? 200,
      'message': response.raw.statusMessage ?? '',
      'headers': response.headers,
      'redirects': response.redirectChain,
    };
  } catch (e) {
    AppLog.e('java.connect failed: $e');
    return failedResponse(url.url, e);
  }
};

/// `java.get`、`java.post`、`java.head`：照給的方法與標頭發，不自動跟著
/// 跳轉。失敗時傳回 500 與錯誤訊息。
BlockingTask rawResponse({
  required String method,
  required String url,
  Object? data,
  required Map<String, dynamic> headers,
}) => () async {
  try {
    final response = await HttpClient().client.fetch<dynamic>(
      RequestOptions(
        method: method,
        path: url,
        baseUrl: '',
        data: data,
        headers: headers,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
        extra: <String, dynamic>{
          AppInterceptor.disableManualRedirectHandlingKey: true,
        },
        cancelToken: currentSourceCancelToken,
      ),
    );
    return {
      'body': response.data?.toString() ?? '',
      'url': response.realUri.toString(),
      'requestUrl': url,
      'code': response.statusCode,
      'message': response.statusMessage ?? '',
      'headers': response.headers.map,
      'redirects': _redirectsOf(response),
    };
  } catch (e) {
    AppLog.e('java.${method.toLowerCase()} failed: $e');
    return failedResponse(url, e);
  }
};

/// 請求失敗時給規則 JS 的回應：狀態碼 500，內文是錯誤訊息。
Map<String, Object?> failedResponse(String url, Object error) => {
  'body': error.toString(),
  'url': url,
  'requestUrl': url,
  'code': 500,
  'message': error.toString(),
  'headers': <String, Object?>{},
  'redirects': const <String>[],
};

List<String> _redirectsOf(Response<dynamic> response) {
  final nativeRedirects = [
    for (final record in response.redirects) record.location.toString(),
  ];
  if (nativeRedirects.isNotEmpty) return nativeRedirects;
  return [
    for (final item
        in (response.extra['_manualRedirectChain'] as List?) ?? const [])
      item.toString(),
  ];
}

/// 回應的位元組。
BlockingTask responseBytes(AnalyzeUrl url) =>
    () => url.getByteArray();

/// [url] 的位元組，不經書源設定（字型這類資源）。
BlockingTask plainBytes(String url) => () async {
  final response = await HttpClient().client.get<List<int>>(
    url,
    options: Options(responseType: ResponseType.bytes),
    cancelToken: currentSourceCancelToken,
  );
  return Uint8List.fromList(response.data ?? const []);
};

/// `java.cacheFile`：快取裡有就用，沒有就抓回來存進快取。存的時候不等它
/// 寫完：停住的書源 isolate 手上若有交易，寫入要等它，它又在等這裡。
BlockingTask cachedText(String url, int saveTimeSeconds) => () async {
  final key = JsEncodeUtils.md5Encode16(url);
  final cached = await CacheManager().get(key);
  if (cached != null) return cached;
  try {
    final response = await HttpClient().client.get<String>(
      url,
      cancelToken: currentSourceCancelToken,
    );
    final content = response.data.toString();
    if (content.isNotEmpty) {
      unawaited(
        CacheManager().put(key, content, saveTimeSeconds: saveTimeSeconds),
      );
    }
    return content;
  } catch (_) {
    return '';
  }
};

/// 看不到的瀏覽器載入網頁（`java.webView` 這一類），傳回內文。
BlockingTask backstagePage({
  String? html,
  String? url,
  String? javaScript,
  String? sourceRegex,
  String? overrideUrlRegex,
}) => () async {
  final webView = BackstageWebView(
    html: html,
    url: url,
    javaScript: javaScript,
    sourceRegex: sourceRegex,
    overrideUrlRegex: overrideUrlRegex,
  );
  final response = await untilCancelled(
    webView.getStrResponse(),
    currentSourceCancelToken,
  );
  return response['body']?.toString() ?? '';
};

/// `java.downloadFile`：下載到暫存資料夾，傳回路徑；失敗時是空字串。
BlockingTask downloadToTemp(String url) => () async {
  try {
    final key = JsEncodeUtils.md5Encode16(url);
    final tempDir = await AppStoragePaths.temporaryDir();
    final savePath = p.join(tempDir.path, 'downloads', key);
    final file = File(savePath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await HttpClient().client.download(
      url,
      savePath,
      cancelToken: currentSourceCancelToken,
    );
    return savePath;
  } catch (e) {
    AppLog.e('java.downloadFile failed: $e');
    return '';
  }
};

/// `java.unArchiveFile`：解壓文件資料夾裡的 [relPath] 到暫存資料夾，傳回
/// 相對暫存資料夾的路徑；失敗時是空字串。
BlockingTask unArchive(String relPath) => () async {
  try {
    final docs = await AppStoragePaths.documentsDir();
    final file = File(p.join(docs.path, relPath));
    if (!await file.exists()) return '';
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    final tempDir = await AppStoragePaths.temporaryDir();
    final outPath = p.join(
      tempDir.path,
      'ArchiveTemp',
      JsEncodeUtils.md5Encode16(file.path),
    );
    final outputDirectory = Directory(outPath);
    if (await outputDirectory.exists()) {
      await outputDirectory.delete(recursive: true);
    }
    await outputDirectory.create(recursive: true);
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final entryPath = p.normalize(p.absolute(p.join(outPath, entry.name)));
      if (!p.isWithin(p.normalize(p.absolute(outPath)), entryPath)) {
        AppLog.w('java.unArchiveFile skipped unsafe entry: ${entry.name}');
        continue;
      }
      final outputFile = File(entryPath);
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(entry.content as List<int>);
    }
    return p.relative(outPath, from: tempDir.path);
  } catch (e) {
    AppLog.e('java.unArchiveFile failed: $e');
    return '';
  }
};

/// `java.getTxtInFolder`：暫存資料夾裡 [relPath] 的所有文字檔接在一起。
BlockingTask textInTempFolder(String relPath) => () async {
  try {
    final tempDir = await AppStoragePaths.temporaryDir();
    final folder = Directory(p.join(tempDir.path, relPath));
    if (!await folder.exists()) return '';
    final buffer = StringBuffer();
    for (final file in folder.listSync().whereType<File>()) {
      buffer.writeln(EncodingDetect.decode(await file.readAsBytes()));
    }
    return buffer.toString();
  } catch (e) {
    AppLog.e('java.getTxtInFolder failed: $e');
    return '';
  }
};
