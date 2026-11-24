/// [DEBUG-toc50] 臨時
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/network/network_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helper.dart';

/// 不用 TestWidgetsFlutterBinding：它會把網路請求都擋成 400。
class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

class _TempPaths extends PathProviderPlatform {
  _TempPaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationCachePath() async => root;
  @override
  Future<String?> getExternalStoragePath() async => root;
}

void main() {
  _MinimalServicesBinding.ensureInitialized();

  final root = Directory.systemTemp.createTempSync('night_reader_live_');
  setUpAll(() async {
    quickJsUnavailableReason();
    PathProviderPlatform.instance = _TempPaths(root.path);
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    registerDatabase(AppDatabase());
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    await NetworkService().init(ephemeral: true);
    SourceIsolate.enabled = true;
    SourceIsolate.start();
  });
  tearDownAll(() async {
    await SourceIsolate.stop();
    await AppDatabase().close();
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // 資料庫檔案在 Windows 上可能還被鎖著；暫存資料夾留給系統清。
    }
  });

  final env = Platform.environment;
  final path = env['NR_SOURCES']!;
  final keywords = (env['NR_KEYWORD'] ?? '诡秘之主,斗罗大陆').split(',');
  final only = env['NR_ONLY'];
  final parallel = int.tryParse(env['NR_PARALLEL'] ?? '') ?? 6;
  final decoded = jsonDecode(File(path).readAsStringSync()) as List;
  final sources = [
    for (final json in decoded.cast<Map<String, dynamic>>())
      if ((json['bookSourceType'] as int? ?? 0) == 0 &&
          (only == null || (json['bookSourceName'] as String).contains(only)) &&
          (env['NR_NOTOC'] == null ||
              (((json['ruleBookInfo'] as Map?)?['tocUrl'] as String?) ?? '')
                  .trim()
                  .isEmpty) &&
          (env['NR_ALL'] != null ||
              ((json['ruleToc'] is Map) &&
                  ((json['ruleToc']['nextTocUrl'] as String?) ?? '')
                      .trim()
                      .isNotEmpty)))
        json,
  ];
  final service = BookSourceService();

  Future<void> fetch(int i, Map<String, dynamic> json) async {
    final source = BookSource.fromJson(json);
    final name = source.bookSourceName;
    for (final keyword in keywords) {
      try {
        final found = await service
            .searchBooks(source, keyword)
            .timeout(const Duration(seconds: 30));
        final hit = found.where((b) => b.name.contains(keyword)).toList();
        if (hit.isEmpty) {
          debugPrint(
            '[DEBUG-toc50] $i $name | $keyword | 搜尋沒有 ${found.length}',
          );
          continue;
        }
        final book = await service
            .getBookInfo(
              source,
              hit.first.toBook().copyWith(
                origin: source.bookSourceUrl,
                originName: name,
              ),
            )
            .timeout(const Duration(seconds: 30));
        final chapters =
            (await service
                    .getChapterList(source, book)
                    .timeout(const Duration(seconds: 180)))
                .where((c) => !c.isVolume)
                .toList();
        if (env['NR_NOTOC'] != null) {
          if (book.tocUrl == book.bookUrl) {
            debugPrint('[DEBUG-toc50] $i $name | 同 | ${chapters.length}');
            return;
          }
          final reset = book.copyWith()..tocUrl = book.bookUrl;
          var legado = -1;
          var err = '';
          try {
            legado =
                (await service
                        .getChapterList(source, reset)
                        .timeout(const Duration(seconds: 180)))
                    .where((c) => !c.isVolume)
                    .length;
          } catch (e) {
            err = e.toString().split('\n').first;
          }
          debugPrint(
            '[DEBUG-toc50] $i $name | 異 | 夜讀 ${chapters.length} | Legado $legado $err | ${book.name} | book:${book.bookUrl} | toc:${book.tocUrl}',
          );
          return;
        }
        debugPrint(
          '[DEBUG-toc50] $i $name | ${book.name} | ${chapters.length} 章 | 最新:${book.latestChapterTitle} | 末:${chapters.isEmpty ? '' : chapters.last.title} | book:${book.bookUrl} | toc:${book.tocUrl} | first:${chapters.isEmpty ? "" : chapters.first.title} | urls:${chapters.take(3).map((c) => c.url).join(" ")}',
        );
        return;
      } catch (e) {
        debugPrint(
          '[DEBUG-toc50] $i $name | $keyword | 錯 ${e.toString().split('\n').first}',
        );
      }
    }
  }

  test('${sources.length} 個書源', () async {
    var next = 0;
    Future<void> worker() async {
      while (next < sources.length) {
        final i = next++;
        await fetch(i, sources[i]);
      }
    }

    await Future.wait([for (var i = 0; i < parallel; i++) worker()]);
  }, timeout: const Timeout(Duration(minutes: 60)));
}
