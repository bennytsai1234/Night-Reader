import 'dart:io' as io;

import 'package:night_reader/core/storage/reader_layout_cache.dart';

import '../core/hybrid_types.dart';
import '../measure/chapter_plan_disk_cache.dart';
import '../measure/metrics_disk_cache.dart';

/// 一本書的換行計畫與段落尺寸磁碟快取（位置與清理見
/// [ReaderLayoutCache]）。
///
/// 只用來加速：讀不到、寫不進去都當作沒有快取，不會讓章節載入或排版
/// 失敗。兩個快取在第一次用到時才打開。
final class HybridLayoutDiskCache {
  HybridLayoutDiskCache({required this.bookUrl});

  final String bookUrl;
  MetricsDiskCache? _metrics;
  ChapterPlanDiskCache? _plans;

  /// [text] 在 [fingerprint] 下存過的換行計畫；沒有或對不上時回傳 null。
  Future<ChapterBlocks?> readPlan(
    ChapterText text,
    StyleFingerprint fingerprint,
  ) async {
    try {
      final cache = await _obtainPlans();
      return await cache.read(
        bookUrl: bookUrl,
        fingerprint: fingerprint,
        text: text,
      );
    } on Exception {
      // 快取只用來省掉換行計算；取不到就照常排版，不能讓章節載入失敗。
      return null;
    }
  }

  Future<void> writePlan(
    ChapterBlocks blocks,
    StyleFingerprint fingerprint,
  ) async {
    try {
      final cache = await _obtainPlans();
      await cache.write(
        bookUrl: bookUrl,
        fingerprint: fingerprint,
        blocks: blocks,
      );
    } on Exception {
      // 寫不進去只是下次要重算換行，不影響這次排版。
    }
  }

  /// 把 [blocks] 這一章存過的段落尺寸交給 [put]。
  Future<void> warmMetrics(
    ChapterBlocks blocks, {
    required MeasurementNamespace namespace,
    required void Function(BlockKey key, BlockMetrics metrics) put,
  }) async {
    try {
      final cache = await _obtainMetrics();
      await cache.warmIntoStore(
        bookUrl: bookUrl,
        namespace: namespace,
        chapterLayoutIdentities: {blocks.chapterIndex: blocks.layoutIdentity},
        put: put,
      );
    } on io.FileSystemException {
      // 磁碟快取只用來加速；讀不到就照常量測。
    }
  }

  Future<void> writeMetrics(
    Map<BlockKey, BlockMetrics> snapshot, {
    required StyleFingerprint fingerprint,
    required Map<int, String> chapterLayoutIdentities,
  }) async {
    if (snapshot.isEmpty) return;
    try {
      final cache = await _obtainMetrics();
      await cache.write(
        bookUrl: bookUrl,
        fingerprint: fingerprint,
        metrics: snapshot,
        chapterLayoutIdentities: chapterLayoutIdentities,
      );
    } on io.FileSystemException {
      // 寫不進去只是少了下次的加速，不影響這次排版。
    }
  }

  Future<MetricsDiskCache> _obtainMetrics() async {
    final existing = _metrics;
    if (existing != null) return existing;
    final directory = await ReaderLayoutCache.baseDirectory();
    return _metrics = MetricsDiskCache(baseDirectory: directory);
  }

  Future<ChapterPlanDiskCache> _obtainPlans() async {
    final existing = _plans;
    if (existing != null) return existing;
    return _plans = ChapterPlanDiskCache(
      baseDirectory: await ReaderLayoutCache.baseDirectory(),
      buildSignature: await ReaderLayoutCache.currentBuild(),
    );
  }
}
