import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/resource_service.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:night_reader/core/storage/storage_metrics.dart';
import 'package:path/path.dart' as p;

class BookCoverStorageService {
  static final BookCoverStorageService _instance =
      BookCoverStorageService._internal();
  factory BookCoverStorageService() => _instance;
  BookCoverStorageService._internal();

  final Dio _dio = Dio();

  Future<void> ensureBookCoverStored(Book book) async {
    final source = book.coverUrl?.trim();
    if (source == null || source.isEmpty) return;
    final path = await _storeCoverSource(
      book: book,
      source: source,
      prefix: 'cover',
    );
    if (path != null && path.isNotEmpty) {
      book.coverLocalPath = path;
    }
  }

  Future<void> ensureCustomCoverStored(Book book) async {
    final source = book.customCoverUrl?.trim();
    if (source == null || source.isEmpty) {
      book.customCoverLocalPath = null;
      return;
    }
    final path = await _storeCoverSource(
      book: book,
      source: source,
      prefix: 'custom-cover',
    );
    if (path != null && path.isNotEmpty) {
      book.customCoverLocalPath = path;
    }
  }

  Future<void> ensureDisplayCoverStored(Book book) async {
    if ((book.customCoverUrl ?? '').trim().isNotEmpty) {
      await ensureCustomCoverStored(book);
      return;
    }
    await ensureBookCoverStored(book);
  }

  Future<void> deleteBookAssets(Book book) async {
    final dir = await AppStoragePaths.bookAssetDir(bookStorageKey(book));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    book.coverLocalPath = null;
    book.customCoverLocalPath = null;
  }

  Future<int> getBookAssetSize(Book book) async {
    final dir = await AppStoragePaths.bookAssetDir(bookStorageKey(book));
    return StorageMetrics.directorySize(dir);
  }

  static String bookStorageKey(Book book) {
    final material = '${book.origin}\n${book.bookUrl}';
    return sha1.convert(utf8.encode(material)).toString();
  }

  Future<String?> _storeCoverSource({
    required Book book,
    required String source,
    required String prefix,
  }) async {
    try {
      final bytes = await _readCoverBytes(source);
      if (bytes == null || bytes.isEmpty) return null;

      final dir = await AppStoragePaths.bookAssetDir(
        bookStorageKey(book),
        ensureExists: true,
      );
      final sourceHash = sha1.convert(utf8.encode(source)).toString();
      final file = File(
        p.join(dir.path, '$prefix-$sourceHash${_extensionForSource(source)}'),
      );
      if (await file.exists() && await file.length() == bytes.length) {
        return file.path;
      }
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e, stack) {
      AppLog.e('保存本地封面失敗: $e', error: e, stackTrace: stack);
      return null;
    }
  }

  Future<Uint8List?> _readCoverBytes(String source) async {
    if (source.startsWith('memory://')) {
      return ResourceService().getMemoryResource(source);
    }
    if (source.startsWith('local://')) {
      final file = File(source.replaceFirst('local://', ''));
      if (!await file.exists()) return null;
      return file.readAsBytes();
    }
    if (source.startsWith('file://')) {
      final file = File(Uri.parse(source).toFilePath());
      if (!await file.exists()) return null;
      return file.readAsBytes();
    }
    final uri = Uri.tryParse(source);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final response = await _dio.get<List<int>>(
        source,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      return data == null ? null : Uint8List.fromList(data);
    }
    final file = File(source);
    if (await file.exists()) {
      return file.readAsBytes();
    }
    return null;
  }

  String _extensionForSource(String source) {
    final uri = Uri.tryParse(source);
    final rawPath = uri?.path.isNotEmpty == true ? uri!.path : source;
    final ext = p.extension(rawPath).toLowerCase();
    if (const {'.jpg', '.jpeg', '.png', '.webp', '.gif'}.contains(ext)) {
      return ext;
    }
    return '.jpg';
  }
}
