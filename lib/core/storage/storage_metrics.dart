import 'dart:io';

import 'package:reader/core/services/app_log_service.dart';

class StorageMetrics {
  static Future<int> directorySize(Directory dir) async {
    var totalSize = 0;
    try {
      if (await dir.exists()) {
        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }
    } catch (error) {
      AppLog.e(
        'Error calculating dir size for ${dir.path}: $error',
        error: error,
      );
    }
    return totalSize;
  }
}
