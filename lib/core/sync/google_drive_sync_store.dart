import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'google_drive_auth.dart';
import 'sync_store.dart';

/// 放在使用者 Google 雲端硬碟的同步空間：App 專屬的隱藏資料夾
/// （`appDataFolder`），使用者在雲端硬碟裡看不到，也只有夜讀讀得到
/// （ADR 0039）。用 Drive REST v3。
///
/// 雲端硬碟沒有「版本不同就不寫」：寫之前再查一次版本，和讀的時候不同就當
/// 成被別台搶先（[SyncConflict]）。查完到寫入之間的極短空檔仍可能被蓋掉，
/// 被蓋掉的那台下次同步會再合併回去（`decideSync` 的「雲端被蓋掉」）。
class GoogleDriveSyncStore implements SyncStore {
  GoogleDriveSyncStore({required this._auth, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  final GoogleDriveAuth _auth;
  final Dio _dio;

  static const String _api = 'https://www.googleapis.com/drive/v3/files';
  static const String _upload =
      'https://www.googleapis.com/upload/drive/v3/files';

  @override
  Future<void> check() async {
    final response = await _send(
      _api,
      'GET',
      query: {
        'spaces': 'appDataFolder',
        'pageSize': '1',
        'fields': 'files(id)',
      },
    );
    _ensureOk(response);
  }

  /// 同名的檔：最早建的那個。兩台第一次同時寫入會各建一個，之後都讀寫
  /// 最早的那個；另一個裡的紀錄這台的上次同步紀錄看得出雲端沒有，下次再送。
  Future<({String id, String version})?> _find(String name) async {
    final response = await _send(
      _api,
      'GET',
      query: {
        'spaces': 'appDataFolder',
        'q': "name = '${name.replaceAll("'", r"\'")}' and trashed = false",
        'orderBy': 'createdTime',
        'fields': 'files(id,version)',
      },
    );
    _ensureOk(response);
    final json = jsonDecode(utf8.decode(response.data ?? Uint8List(0)));
    final files = json is Map ? json['files'] : null;
    if (files is! List || files.isEmpty) return null;
    final first = files.first;
    if (first is! Map || first['id'] is! String) return null;
    return (id: first['id'] as String, version: '${first['version']}');
  }

  @override
  Future<SyncFile?> read(String name) async {
    final file = await _find(name);
    if (file == null) return null;
    final response = await _send(
      '$_api/${file.id}',
      'GET',
      query: {'alt': 'media'},
    );
    if (response.statusCode == 404) return null;
    _ensureOk(response);
    return SyncFile(
      utf8.decode(response.data ?? Uint8List(0), allowMalformed: true),
      version: file.version,
    );
  }

  @override
  Future<String?> version(String name) async => (await _find(name))?.version;

  @override
  Future<void> write(
    String name,
    String content, {
    String? ifVersion,
    bool ifAbsent = false,
  }) async {
    final current = await _find(name);
    if (ifAbsent && current != null) throw const SyncConflict();
    if (ifVersion != null && current?.version != ifVersion) {
      throw const SyncConflict();
    }
    final bytes = utf8.encode(content);
    if (current != null) {
      final response = await _send(
        '$_upload/${current.id}',
        'PATCH',
        query: {'uploadType': 'media'},
        headers: {Headers.contentTypeHeader: 'application/json'},
        data: bytes,
      );
      _ensureOk(response);
      return;
    }
    const boundary = 'night_reader_sync_boundary';
    final body = BytesBuilder()
      ..add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Type: application/json; charset=UTF-8\r\n\r\n'
          '${jsonEncode({
            'name': name,
            'parents': ['appDataFolder'],
          })}\r\n'
          '--$boundary\r\n'
          'Content-Type: application/json\r\n\r\n',
        ),
      )
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--'));
    final response = await _send(
      _upload,
      'POST',
      query: {'uploadType': 'multipart'},
      headers: {
        Headers.contentTypeHeader: 'multipart/related; boundary=$boundary',
      },
      data: body.takeBytes(),
    );
    _ensureOk(response);
  }

  /// 帶上授權送出；Google 說 token 失效（401）就丟掉、重取一次再送。
  Future<Response<Uint8List>> _send(
    String url,
    String method, {
    Map<String, String> query = const {},
    Map<String, Object?> headers = const {},
    Object? data,
  }) async {
    var response = await _request(url, method, query, headers, data);
    if (response.statusCode == 401) {
      final stale = response.requestOptions.headers['Authorization'];
      if (stale is String && stale.startsWith('Bearer ')) {
        await _auth.forget(stale.substring(7));
      }
      response = await _request(url, method, query, headers, data);
    }
    return response;
  }

  Future<Response<Uint8List>> _request(
    String url,
    String method,
    Map<String, String> query,
    Map<String, Object?> headers,
    Object? data,
  ) async {
    final token = await _auth.token();
    try {
      return await _dio.request<Uint8List>(
        url,
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          headers: {'Authorization': 'Bearer $token', ...headers},
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (error) {
      throw SyncStoreException(switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => '連線逾時，稍後再試',
        _ => '連不上 Google 雲端硬碟，檢查網路',
      });
    }
  }

  static void _ensureOk(Response<Object?> response) {
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return;
    throw SyncStoreException(switch (status) {
      401 => 'Google 帳號的授權失效了，到「同步空間」重新登入',
      403 => 'Google 雲端硬碟拒絕存取（HTTP 403），稍後再試',
      _ => 'Google 雲端硬碟回應錯誤（HTTP $status）',
    });
  }
}
