import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'sync_store.dart';

/// 放在 WebDAV（堅果雲、Nextcloud、NAS）的同步空間，同 Legado：使用者填網址、
/// 帳號、密碼，同步檔放在那個網址底下的 [folder] 資料夾。
class WebDavSyncStore implements SyncStore {
  WebDavSyncStore({
    required String url,
    required String user,
    required String password,
    Dio? dio,
  }) : _root = _withSlash(url.trim()),
       _auth = 'Basic ${base64.encode(utf8.encode('$user:$password'))}',
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               sendTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(seconds: 30),
             ),
           );

  static const String folder = 'NightReader/';

  final String _root;
  final String _auth;
  final Dio _dio;

  static String _withSlash(String url) => url.endsWith('/') ? url : '$url/';

  String get _folderUrl => '$_root$folder';

  String _fileUrl(String name) => '$_folderUrl${Uri.encodeComponent(name)}';

  @override
  Future<void> check() async {
    final uri = Uri.tryParse(_root);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const SyncStoreException('網址不對，要以 https:// 開頭');
    }
    final response = await _send(_root, 'PROPFIND', headers: {'Depth': '0'});
    if (response.statusCode == 404) {
      throw const SyncStoreException('這個網址找不到 WebDAV');
    }
    _ensureOk(response);
    await _makeFolder();
  }

  @override
  Future<SyncFile?> read(String name) async {
    final response = await _send(_fileUrl(name), 'GET');
    if (response.statusCode == 404) return null;
    _ensureOk(response);
    final bytes = response.data ?? Uint8List(0);
    return SyncFile(
      utf8.decode(bytes, allowMalformed: true),
      version: _strongEtag(response.headers.value('etag')),
    );
  }

  @override
  Future<void> write(
    String name,
    String content, {
    String? ifVersion,
    bool ifAbsent = false,
  }) async {
    Future<Response<Uint8List>> put() => _send(
      _fileUrl(name),
      'PUT',
      headers: {
        Headers.contentTypeHeader: 'application/json; charset=utf-8',
        'If-Match': ?ifVersion,
        if (ifAbsent) 'If-None-Match': '*',
      },
      data: utf8.encode(content),
    );

    var response = await put();
    // 資料夾還沒建（第一次同步、或被使用者刪掉）時 WebDAV 回 409 或 404。
    if (response.statusCode == 409 || response.statusCode == 404) {
      await _makeFolder();
      response = await put();
    }
    if (response.statusCode == 412) throw const SyncConflict();
    _ensureOk(response);
  }

  Future<void> _makeFolder() async {
    final response = await _send(_folderUrl, 'MKCOL');
    // 405：資料夾已經在了。
    if (response.statusCode == 405) return;
    _ensureOk(response);
  }

  Future<Response<Uint8List>> _send(
    String url,
    String method, {
    Map<String, Object?> headers = const {},
    Object? data,
  }) async {
    try {
      return await _dio.request<Uint8List>(
        url,
        data: data,
        options: Options(
          method: method,
          headers: {'Authorization': _auth, ...headers},
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
          followRedirects: false,
        ),
      );
    } on DioException catch (error) {
      throw SyncStoreException(switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => '連線逾時，稍後再試',
        DioExceptionType.badCertificate => '同步空間的憑證有問題',
        _ => '連不上同步空間，檢查網址與網路',
      });
    }
  }

  static void _ensureOk(Response<Object?> response) {
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return;
    if (status == 401 || status == 403) {
      throw const SyncStoreException('帳號或密碼不對');
    }
    throw SyncStoreException('同步空間回應錯誤（HTTP $status）');
  }

  /// 只用強 ETag 做寫入前的比對：弱 ETag（`W/` 開頭）在 If-Match 裡一律
  /// 不相符，帶了就永遠寫不進去。
  static String? _strongEtag(String? etag) {
    if (etag == null || etag.isEmpty || etag.startsWith('W/')) return null;
    return etag;
  }
}
