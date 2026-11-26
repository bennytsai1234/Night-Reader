import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'google_drive_auth.dart';
import 'sync_store.dart';

/// 放在使用者 Google 雲端硬碟的同步空間：App 專屬的隱藏資料夾
/// （`appDataFolder`），使用者在雲端硬碟裡看不到，也只有夜讀讀得到
/// （ADR 0039）。用 Drive REST v3。
///
/// Drive v3 沒有「版本不同就不寫」：寫之前再查一次版本，和讀的時候不同就當
/// 成被別台搶先（[SyncConflict]）。查完到寫入落地之間別台寫的會被蓋掉，
/// 要等被蓋掉的那台再同步一次才合併回去（`decideSync` 的「雲端被蓋掉」，
/// ADR 0039）。
class GoogleDriveSyncStore implements SyncStore {
  GoogleDriveSyncStore({required this._auth, required this._account, Dio? dio})
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

  /// 同步空間記的 Google 帳號；每次都取這個帳號的授權。
  final String _account;
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
  /// 雲端硬碟可能回一頁空的、附上下一頁，要翻到有檔或沒有下一頁才算沒有。
  Future<({String id, String version})?> _find(String name) async {
    String? pageToken;
    do {
      final response = await _send(
        _api,
        'GET',
        query: {
          'spaces': 'appDataFolder',
          'q': "name = '${name.replaceAll("'", r"\'")}' and trashed = false",
          'orderBy': 'createdTime',
          'fields': 'nextPageToken,files(id,version)',
          'pageToken': ?pageToken,
        },
      );
      _ensureOk(response);
      final json = jsonDecode(utf8.decode(response.data ?? Uint8List(0)));
      if (json is! Map) return null;
      final files = json['files'];
      if (files is List && files.isNotEmpty) {
        final first = files.first;
        if (first is! Map || first['id'] is! String) return null;
        return (id: first['id'] as String, version: '${first['version']}');
      }
      final next = json['nextPageToken'];
      pageToken = next is String && next.isNotEmpty ? next : null;
    } while (pageToken != null);
    return null;
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

  @override
  Future<Uint8List?> readBytes(String name) async {
    final file = await _find(name);
    if (file == null) return null;
    final response = await _send(
      '$_api/${file.id}',
      'GET',
      query: {'alt': 'media'},
      transfer: true,
    );
    if (response.statusCode == 404) return null;
    _ensureOk(response);
    return response.data ?? Uint8List(0);
  }

  /// 原檔常超過 5 MB，而 Drive 一次送完的上傳（[write] 用的 multipart、
  /// media）只收 5 MB 以內，所以用可續傳上傳：先開一個上傳工作，再把整個檔
  /// 送到它給的網址。
  @override
  Future<void> writeBytes(String name, Uint8List bytes) async {
    final current = await _find(name);
    final start = await _send(
      current == null ? _upload : '$_upload/${current.id}',
      current == null ? 'POST' : 'PATCH',
      query: {'uploadType': 'resumable'},
      headers: {
        Headers.contentTypeHeader: 'application/json; charset=UTF-8',
        'X-Upload-Content-Type': 'application/octet-stream',
        'X-Upload-Content-Length': '${bytes.length}',
      },
      data: utf8.encode(
        jsonEncode({
          if (current == null) ...{
            'name': name,
            'parents': ['appDataFolder'],
          },
        }),
      ),
    );
    _ensureOk(start);
    final location = start.headers.value('location');
    if (location == null || location.isEmpty) {
      throw const SyncStoreException.file('Google 雲端硬碟沒有給上傳的網址');
    }
    final response = await _send(
      location,
      'PUT',
      headers: {Headers.contentTypeHeader: 'application/octet-stream'},
      data: bytes,
      transfer: true,
    );
    _ensureOk(response);
  }

  /// 同名的檔都刪掉（兩台第一次同時寫入會各建一個，[_find]），刪到查不到
  /// 為止；刪不完就算這個檔失敗，下次再刪。
  @override
  Future<void> delete(String name) async {
    for (var i = 0; i < 20; i++) {
      final file = await _find(name);
      if (file == null) return;
      final response = await _send('$_api/${file.id}', 'DELETE');
      // 404：剛被別台刪掉，再查一次還有沒有別的同名檔。
      if (response.statusCode != 404) _ensureOk(response);
    }
    throw const SyncStoreException.file('Google 雲端硬碟裡的同名檔刪不完，稍後再試');
  }

  /// 傳本地書原檔（[transfer]）時一本可能幾十 MB，行動數據要傳好幾分鐘，
  /// 不用同步檔的 30 秒上限。
  static const Duration transferTimeout = Duration(minutes: 10);

  /// 帶上授權送出；Google 說 token 失效（401）就丟掉、重取一次再送。
  Future<Response<Uint8List>> _send(
    String url,
    String method, {
    Map<String, String> query = const {},
    Map<String, Object?> headers = const {},
    Object? data,
    bool transfer = false,
  }) async {
    var response = await _request(url, method, query, headers, data, transfer);
    if (response.statusCode == 401) {
      final stale = response.requestOptions.headers['Authorization'];
      if (stale is String && stale.startsWith('Bearer ')) {
        await _auth.forget(stale.substring(7));
      }
      response = await _request(url, method, query, headers, data, transfer);
    }
    return response;
  }

  Future<Response<Uint8List>> _request(
    String url,
    String method,
    Map<String, String> query,
    Map<String, Object?> headers,
    Object? data,
    bool transfer,
  ) async {
    final token = await _auth.token(_account);
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
          sendTimeout: transfer ? transferTimeout : null,
          receiveTimeout: transfer ? transferTimeout : null,
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
    // 整個空間都用不了的才中止整輪：授權失效（401）、被限流（429，或 403
    // 帶著限流的原因）、伺服器故障（5xx）。其他（403 拒絕存取這份檔、404
    // 這類）只算這一份檔案的事，其他檔案照常同步（#205）。
    if (status == 401) {
      throw const SyncStoreException('Google 帳號的授權失效了，到「同步空間」重新登入');
    }
    if (status == 429 || (status == 403 && _rateLimited(response.data))) {
      throw SyncStoreException('Google 雲端硬碟要求放慢速度（HTTP $status），稍後再試');
    }
    if (status >= 500) {
      throw SyncStoreException('Google 雲端硬碟暫時無法使用（HTTP $status），稍後再試');
    }
    if (status == 403) {
      throw const SyncStoreException.file('Google 雲端硬碟拒絕存取（HTTP 403），稍後再試');
    }
    throw SyncStoreException.file('Google 雲端硬碟回應錯誤（HTTP $status）');
  }

  /// Google 限流時回 403，錯誤內容的原因是 `userRateLimitExceeded`、
  /// `rateLimitExceeded`（新格式寫成 `RATE_LIMIT_EXCEEDED`）。
  static bool _rateLimited(Object? data) {
    final text = switch (data) {
      final Uint8List bytes => utf8.decode(bytes, allowMalformed: true),
      final String text => text,
      _ => '',
    }.toLowerCase();
    return text.contains('ratelimitexceeded') ||
        text.contains('rate_limit_exceeded');
  }
}
