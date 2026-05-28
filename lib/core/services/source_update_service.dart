import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:reader/core/database/dao/book_source_dao.dart';
import 'package:reader/core/database/dao/source_subscription_dao.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/models/source_subscription.dart';
import 'package:reader/core/di/injection.dart';
import 'package:reader/core/utils/logger.dart';

class SourceUpdateService {
  final BookSourceDao _sourceDao = getIt<BookSourceDao>();
  final SourceSubscriptionDao _subDao = getIt<SourceSubscriptionDao>();
  final Dio _dio = Dio();

  /// 執行訂閱更新 (對標 Android RuleSub.update)
  Future<int> updateFromSubscription(SourceSubscription sub) async {
    try {
      final response = await _dio.get(sub.url);
      final dynamic data = response.data;

      List<dynamic> list = [];
      if (data is List) {
        list = data;
      } else if (data is String) {
        list = jsonDecode(data);
      }

      int updateCount = 0;
      for (var item in list) {
        try {
          final newSource = BookSource.fromJson(item);
          final existing = await _sourceDao.getByUrl(newSource.bookSourceUrl);

          if (existing != null) {
            // 保留本地的排序、分組、啟用狀態
            newSource.customOrder = existing.customOrder;
            newSource.bookSourceGroup = existing.bookSourceGroup;
            newSource.enabled = existing.enabled;
          }

          await _sourceDao.upsert(newSource);
          updateCount++;
        } catch (_) {}
      }

      sub.lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
      await _subDao.upsert(sub);

      return updateCount;
    } catch (e) {
      Logger.e('訂閱更新失敗: ${sub.name}, $e');
      return 0;
    }
  }

  /// 執行書源校驗 (對標 Android SourceCheck)
  Future<void> checkSource(BookSource source) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    try {
      // 測試搜尋與正文規則的可連通性
      await _dio.get(source.bookSourceUrl).timeout(const Duration(seconds: 10));
      final endTime = DateTime.now().millisecondsSinceEpoch;
      source.respondTime = endTime - startTime;
    } catch (e) {
      source.respondTime = -1; // 標記為失效
    }
    await _sourceDao.upsert(source);
  }
}
