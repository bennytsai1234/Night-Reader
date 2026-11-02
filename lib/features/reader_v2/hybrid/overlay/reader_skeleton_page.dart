import 'dart:convert';
import 'dart:ui';

import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 上次離開閱讀器時畫面上的那一頁：每一行字在正文區的位置，和當時的閱讀
/// 進度。下次從同一個位置、用同樣的版面開這本書時，紙上的骨架照它畫，頁尾
/// 的進度骨架照當時的字樣量寬度；骨架換場時每一條剛好換成那一行字
/// （ADR 0024）。
final class ReaderSkeletonPage {
  const ReaderSkeletonPage({
    required this.chapterIndex,
    required this.charOffset,
    required this.visualOffsetPx,
    required this.layout,
    required this.contentHash,
    required this.lines,
    this.titleLines = const <int>{},
    this.progress,
  });

  final int chapterIndex;
  final int charOffset;
  final double visualOffsetPx;

  /// 記下時的版面（[layoutKeyOf]）；版面不同時行的位置對不上，不用。
  final String layout;

  /// 記下時這一章的正文（`ChapterBlocks.contentHash`）。替換規則或重新取得
  /// 換了正文時，同一個位置的行不再是記下的那些，開書取到正文後比對。
  final String contentHash;

  /// 每一行字在正文區的範圍（正文區座標，由上而下）。
  final List<Rect> lines;

  /// [lines] 裡章名那幾行的索引。
  final Set<int> titleLines;
  final HybridProgressSnapshot? progress;

  /// 開書的位置與版面都和記下時相同。位置比到半個像素：存進資料庫再讀
  /// 出來的捲動餘量可能有小數誤差。
  bool matches(ReaderV2Location location, ReaderV2LayoutSpec spec) =>
      location.chapterIndex == chapterIndex &&
      location.charOffset == charOffset &&
      (location.visualOffsetPx - visualOffsetPx).abs() < 0.5 &&
      layout == layoutKeyOf(spec);

  /// 決定每一行落在哪裡的版面參數。不用 [ReaderV2LayoutSpec] 的雜湊：
  /// `Object.hash` 每次啟動 App 都不同，存起來下次比不上。
  static String layoutKeyOf(ReaderV2LayoutSpec spec) {
    final style = spec.style;
    return jsonEncode([
      spec.viewportSize.width,
      spec.viewportSize.height,
      spec.contentWidth,
      spec.contentHeight,
      spec.cellWidth,
      style.fontSize,
      style.lineHeight,
      style.letterSpacing,
      style.paragraphSpacing,
      style.chapterSpacing,
      style.paddingTop,
      style.paddingBottom,
      style.paddingLeft,
      style.paddingRight,
      style.bold,
      style.textIndent,
      style.titleFontSize,
      style.titleSpacing,
      kReaderV2CjkTypographyFeatureSignature,
    ]);
  }

  Map<String, Object?> toJson() => {
    'chapter': chapterIndex,
    'offset': charOffset,
    'visual': visualOffsetPx,
    'layout': layout,
    'content': contentHash,
    // 一位小數就分不出差別，紀錄小一半。
    'lines': [
      for (final line in lines)
        for (final value in [line.left, line.top, line.right, line.bottom])
          (value * 10).round() / 10,
    ],
    if (titleLines.isNotEmpty) 'titles': titleLines.toList()..sort(),
    if (progress case final progress?)
      'progress': [
        progress.chapterIndex,
        progress.chapterCount,
        progress.chapterPercent,
        progress.chapterStart,
        progress.chapterShare,
      ],
  };

  static ReaderSkeletonPage fromJson(Map<String, dynamic> json) {
    final values = [
      for (final value in json['lines'] as List<dynamic>)
        (value as num).toDouble(),
    ];
    final progress = json['progress'] as List<dynamic>?;
    return ReaderSkeletonPage(
      chapterIndex: json['chapter'] as int,
      charOffset: json['offset'] as int,
      visualOffsetPx: (json['visual'] as num).toDouble(),
      layout: json['layout'] as String,
      contentHash: json['content'] as String,
      titleLines: {
        for (final index in json['titles'] as List<dynamic>? ?? const [])
          index as int,
      },
      lines: [
        for (var i = 0; i + 3 < values.length; i += 4)
          Rect.fromLTRB(values[i], values[i + 1], values[i + 2], values[i + 3]),
      ],
      progress: progress == null
          ? null
          : HybridProgressSnapshot(
              chapterIndex: progress[0] as int,
              chapterCount: progress[1] as int,
              chapterPercent: (progress[2] as num).toDouble(),
              // 加權前存的紀錄只有前三項，照章數平均。
              chapterStart: progress.length > 4
                  ? (progress[3] as num).toDouble()
                  : null,
              chapterShare: progress.length > 4
                  ? (progress[4] as num).toDouble()
                  : null,
            ),
    );
  }
}

/// 每本書最近一次的 [ReaderSkeletonPage]，存在偏好設定（開 App 時已整份
/// 讀進記憶體，開書時同步取得，第一幀就畫得出來）。
final class ReaderSkeletonPageStore {
  ReaderSkeletonPageStore(this._prefs);

  final SharedPreferences _prefs;

  static const String key = 'reader_skeleton_pages';

  /// 只留最近讀的幾本：常在幾本書之間切換時都還在，更早讀的書開書時照
  /// 固定樣式畫。一本約 30 行、紀錄 2 KB 上下，十本不到 20 KB。
  static const int keptBooks = 10;

  /// 依讀的先後排的紀錄（最近的在最後）；讀不懂時當作沒有。
  Map<String, dynamic> _all() {
    final saved = _prefs.getString(key);
    if (saved == null) return {};
    try {
      return jsonDecode(saved) as Map<String, dynamic>;
    } catch (error) {
      AppLog.w('閱讀器骨架的紀錄讀不懂，這次照固定樣式畫: $error');
      return {};
    }
  }

  ReaderSkeletonPage? read(String bookUrl) {
    final json = _all()[bookUrl];
    if (json == null) return null;
    try {
      return ReaderSkeletonPage.fromJson(json as Map<String, dynamic>);
    } catch (error) {
      AppLog.w('閱讀器骨架的紀錄讀不懂，這次照固定樣式畫: $error');
      return null;
    }
  }

  Future<void> write(String bookUrl, ReaderSkeletonPage page) async {
    final all = _all()
      ..remove(bookUrl)
      ..[bookUrl] = page.toJson();
    while (all.length > keptBooks) {
      all.remove(all.keys.first);
    }
    try {
      await _prefs.setString(key, jsonEncode(all));
    } catch (error, stackTrace) {
      AppLog.e('閱讀器骨架寫入失敗: $error', error: error, stackTrace: stackTrace);
    }
  }
}
