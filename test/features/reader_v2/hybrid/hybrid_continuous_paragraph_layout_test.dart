import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/measurement_store.dart';
import 'package:night_reader/features/reader_v2/hybrid/paragraph/paragraph_cache.dart';
import 'package:night_reader/features/reader_v2/hybrid/pump/layout_pump.dart';

/// 驗證「效能 block 邊界不得產生視覺硬換行」：同一個邏輯段落，不論被切成
/// 幾個 ChapterBlock（scheduling identity），LayoutPump 產生的連續排版
/// 幾何（斷行邊界、總高度、charOffset→世界座標）都必須與整段不切一致。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 4 個句子（各 14 個 CJK 字 + 句號）+ 1 個含 surrogate pair 的片段
  // （不以句號結尾之外的標點）+ 4 個句子。刻意選一個會讓 Skia 換行落在
  // 「非句界」字元上的內容寬度，確保測試涵蓋句中切、代理對旁切、
  // 跨段落中段等情境，而不是只切在天然斷句處。
  const sentenceBody = '夜讀好書真愉快今晚月色真美麗啊'; // 14 CJK chars
  String _paragraphText() {
    final buffer = StringBuffer();
    for (var i = 0; i < 4; i += 1) {
      buffer.write(sentenceBody);
      buffer.write('。');
    }
    buffer.write('驚喜😀連連。'); // 60..67：含 surrogate pair 的片段
    for (var i = 0; i < 4; i += 1) {
      buffer.write(sentenceBody);
      buffer.write('。');
    }
    return buffer.toString();
  }

  final paragraphText = _paragraphText();

  const fontSize = 20.0;
  const contentWidth = fontSize * 6.3; // 非整數行寬比例，避免巧合對齊句界
  const trailingSpacing = 3.0;
  const textStyle = HybridBlockTextStyle(
    fontSize: fontSize,
    lineHeight: 1.5,
    letterSpacing: 0,
    textAlign: ui.TextAlign.start,
  );

  StyleFingerprint fingerprint() => StyleFingerprint(
    viewportWidth: 320,
    viewportHeight: 640,
    contentWidth: contentWidth,
    contentHeight: 600,
    fontSize: fontSize,
    lineHeight: 1.5,
    letterSpacing: 0,
    paragraphSpacing: 1,
    paddingTop: 8,
    paddingBottom: 8,
    paddingLeft: 16,
    paddingRight: 16,
    textIndent: 0,
    bold: false,
    justify: false,
    textScaleFactor: 1,
    fontFamilySignature: 'system',
    platformFontSignature: 'test',
  );

  /// 依 [cutPoints]（段落內部切點，須為合法 UTF-16 邊界）手動切出一組
  /// ChapterBlock；不經 TextPreprocessor，讓測試能精準控制切點落於句中／
  /// 行中／代理對旁，不受 `_splitParagraph` 內部啟發式牽動。
  List<ChapterBlock> manualSplit(List<int> cutPoints) {
    final offsets = <int>[0, ...cutPoints, paragraphText.length];
    return <ChapterBlock>[
      for (var i = 0; i < offsets.length - 1; i += 1)
        ChapterBlock(
          key: BlockKey(chapterIndex: 0, blockIndex: i),
          text: paragraphText.substring(offsets[i], offsets[i + 1]),
          charRange: HybridTextRange(offsets[i], offsets[i + 1]),
          sourceParagraphIndex: 0,
          isContinuation: i > 0,
        ),
    ];
  }

  LayoutTask taskFor(List<ChapterBlock> group, StyleFingerprint fp) {
    return LayoutTask(
      block: group.first,
      continuationBlocks: group.skip(1).toList(growable: false),
      epoch: LayoutEpoch.initial,
      fingerprint: fp,
      textStyle: textStyle,
      contentWidth: contentWidth,
      trailingSpacing: trailingSpacing,
    );
  }

  double? lineTopForOffset(ui.Paragraph paragraph, int offset, int length) {
    if (length <= 0) return 0.0;
    final safe = offset.clamp(0, length).toInt();
    final start = safe >= length ? length - 1 : safe;
    final boxes = paragraph.getBoxesForRange(start, start + 1);
    if (boxes.isEmpty) return null;
    return boxes.first.top;
  }

  /// 黑箱重現 HybridReaderScreen._visualPositionForChar 的世界座標換算：
  /// 只用 ParagraphCache／MeasurementStore 的公開介面，找出 [chapterOffset]
  /// 視覺上真正落在 group 哪個 block 的 Y 窗、以及該窗內的 local top，
  /// 再累加前面 block 的高度得到世界座標。
  double worldYForOffset({
    required List<ChapterBlock> group,
    required ParagraphCache cache,
    required MeasurementStore store,
    required MeasurementNamespace namespace,
    required int chapterOffset,
  }) {
    final head = group.first;
    final headEntry = cache.acquireEntry(head.key, LayoutEpoch.initial)!;
    final paragraph = headEntry.paragraph;
    final totalLength = group.fold<int>(0, (sum, b) => sum + b.text.length);
    final localOffset = chapterOffset - head.charRange.start;
    final paragraphY =
        lineTopForOffset(paragraph, localOffset, totalLength) ?? 0.0;

    var owningIndex = 0;
    var owningLocalTop = headEntry.localTop;
    for (var i = 0; i < group.length; i += 1) {
      final entry = cache.acquireEntry(group[i].key, LayoutEpoch.initial)!;
      if (entry.localTop <= paragraphY + 0.001) {
        owningIndex = i;
        owningLocalTop = entry.localTop;
      } else {
        break;
      }
    }
    var worldTop = 0.0;
    for (var i = 0; i < owningIndex; i += 1) {
      worldTop += store.get(namespace, group[i].key)!.height;
    }
    return worldTop + (paragraphY - owningLocalTop);
  }

  ({
    ui.Paragraph paragraph,
    ParagraphCache cache,
    MeasurementStore store,
    MeasurementNamespace namespace,
  })
  runSegmentation(List<ChapterBlock> group) {
    final store = MeasurementStore();
    final cache = ParagraphCache();
    final fp = fingerprint();
    final namespace = MeasurementNamespace(
      epoch: LayoutEpoch.initial,
      fingerprint: fp,
    );
    final pump = LayoutPump(
      paragraphCache: cache,
      measurementStore: store,
      namespace: namespace,
    );
    pump.submit(taskFor(group, fp));
    // 整個 group 必須在同一次 pumpPending 完成（連續排版是一次 layout()）。
    expect(pump.pumpPending(), completion(1));
    final paragraph = cache.acquireEntry(group.first.key, LayoutEpoch.initial)!
        .paragraph;
    pump.dispose();
    return (
      paragraph: paragraph,
      cache: cache,
      store: store,
      namespace: namespace,
    );
  }

  test('段落文字 fixture 涵蓋句中切、行中切與 surrogate pair 邊界', () {
    // 66/67 是 😀 的高/低代理；68 緊接在代理對之後，是合法但非句界的切點。
    expect(
      paragraphText.codeUnitAt(66),
      inInclusiveRange(0xD800, 0xDBFF),
      reason: 'fixture 需要在 66 起有一個 surrogate pair',
    );
    expect(paragraphText.codeUnitAt(67), inInclusiveRange(0xDC00, 0xDFFF));
    expect(paragraphText[68 - 1], isNot('。'));
  });

  group('連續段落排版：block 切法不得產生額外硬換行', () {
    late ui.Paragraph reference;
    late List<double> referenceLineTops;

    setUpAll(() {
      final result = runSegmentation(manualSplit(const <int>[]));
      reference = result.paragraph;
      referenceLineTops = [
        for (final line in reference.computeLineMetrics())
          line.baseline - line.ascent,
      ];
    });

    test('測試內容寬度確實讓至少一個切點落在行中（非行首）', () {
      // 取這條測試會用到的其中一個切點（68，緊接 surrogate pair 之後）
      // 驗證它落在某一行的內部，而不是巧合對在行首——否則後面的比較就
      // 測不到「行中切」這個情境。
      var offset = 0;
      var foundMidLine = false;
      for (var i = 0; i < referenceLineTops.length; i += 1) {
        final line = reference.getLineBoundary(
          ui.TextPosition(offset: offset),
        );
        if (68 > line.start && 68 < line.end) foundMidLine = true;
        offset = line.end;
        if (offset >= paragraphText.length) break;
      }
      expect(
        foundMidLine,
        isTrue,
        reason: '切點 68 應落在某一行中間，才能驗證人工邊界不產生硬換行',
      );
    });

    final segmentations = <String, List<int>>{
      '句界對齊切法（4 塊）': const <int>[32, 71, 103],
      '句中＋代理對旁混合切法（3 塊）': const <int>[55, 68],
      '細切法（6 塊，含多個非句界切點）': const <int>[20, 42, 68, 95, 115],
    };

    for (final entry in segmentations.entries) {
      test('${entry.key}：斷行、總高度與逐行 UTF-16 range 與連續排版完全一致', () {
        final group = manualSplit(entry.value);
        final result = runSegmentation(group);

        // 斷行數與逐行 UTF-16 range 必須逐一相同：human-invisible 的
        // block 邊界不能讓 Skia 多斷或少斷一行。
        expect(
          result.paragraph.numberOfLines,
          reference.numberOfLines,
          reason: '${entry.key}：line count 必須與連續排版一致',
        );
        var refOffset = 0;
        var segOffset = 0;
        for (var i = 0; i < reference.numberOfLines; i += 1) {
          final refLine = reference.getLineBoundary(
            ui.TextPosition(offset: refOffset),
          );
          final segLine = result.paragraph.getLineBoundary(
            ui.TextPosition(offset: segOffset),
          );
          expect(
            segLine.start,
            refLine.start,
            reason: '${entry.key}：第 $i 行起點必須相同',
          );
          expect(
            segLine.end,
            refLine.end,
            reason: '${entry.key}：第 $i 行終點必須相同',
          );
          refOffset = refLine.end;
          segOffset = segLine.end;
        }

        // 總高度：group 內每塊 BlockMetrics.height 加總，必須等於連續排版
        // 的 paragraph.height + trailingSpacing（人工邊界不得新增／遺漏
        // 高度；只有 group 真正最後一塊計入 trailingSpacing）。
        var totalHeight = 0.0;
        var totalLineCount = 0;
        for (var i = 0; i < group.length; i += 1) {
          final metrics = result.store.get(result.namespace, group[i].key)!;
          totalHeight += metrics.height;
          totalLineCount += metrics.lineCount;
          if (i < group.length - 1) {
            // 效能切點之間恆為 0 間距——不是語意段落邊界。
            expect(
              result.store.get(result.namespace, group[i + 1].key) != null,
              isTrue,
            );
          }
        }
        expect(
          totalHeight,
          closeTo(reference.height + trailingSpacing, 0.01),
          reason: '${entry.key}：總高度必須等於連續排版 + trailingSpacing',
        );
        expect(
          totalLineCount,
          reference.numberOfLines,
          reason: '${entry.key}：各切塊 lineCount 加總必須等於連續排版行數',
        );

        // charOffset → 世界座標：涵蓋段落中段、每個人工切點前後、句中切點
        // 與 surrogate pair 緊鄰處，逐一與連續排版比較。
        // 排除落在 low surrogate 上的探測點——查詢單一 code unit 的
        // getBoxesForRange 在那裡沒有意義（不是合法的字元起點）。
        bool isLowSurrogateStart(int offset) {
          if (offset < 0 || offset >= paragraphText.length) return false;
          final unit = paragraphText.codeUnitAt(offset);
          return unit >= 0xDC00 && unit <= 0xDFFF;
        }

        final probeOffsets = <int>{
          10,
          65,
          68,
          75,
          paragraphText.length - 5,
          for (final cut in entry.value) ...[
            (cut - 1).clamp(0, paragraphText.length - 1),
            cut.clamp(0, paragraphText.length - 1),
          ],
        }..removeWhere(isLowSurrogateStart);
        for (final offset in probeOffsets) {
          final refY = lineTopForOffset(reference, offset, paragraphText.length)!;
          final segY = worldYForOffset(
            group: group,
            cache: result.cache,
            store: result.store,
            namespace: result.namespace,
            chapterOffset: offset,
          );
          expect(
            segY,
            closeTo(refY, 0.01),
            reason: '${entry.key}：charOffset=$offset 的世界 Y 必須與連續排版一致',
          );
        }

        result.cache.dispose();
      });
    }

    test(
      '同一行落兩個切點：中間切塊 own height 合法為 0，不得頂到整像素造成總高度偏移',
      () {
        // 找一條至少有 3 個字元、且不是最後一行的行，把兩個切點都放進同一
        // 行——這是唯一會讓中間切塊的「own height」真正為 0 的情境（見
        // layout_pump.dart _groupSplitYs／_metricsFromSplitYs：兩個切點的
        // line-top 相同時，中間切塊的視窗寬度就是 0）。
        ui.TextRange? targetLine;
        var offset = 0;
        while (offset < paragraphText.length) {
          final boundary = reference.getLineBoundary(
            ui.TextPosition(offset: offset),
          );
          if (boundary.end - boundary.start >= 3 &&
              boundary.end < paragraphText.length) {
            targetLine = boundary;
            break;
          }
          offset = boundary.end;
        }
        expect(
          targetLine,
          isNotNull,
          reason: 'fixture 需要至少一行有 3+ 字元且非最後一行',
        );
        final line = targetLine!;
        final cut1 = line.start + 1;
        final cut2 = line.start + 2;

        final group = manualSplit(<int>[cut1, cut2]);
        final result = runSegmentation(group);

        // 中間切塊（block 1）own height 必須合法為極小正值（BlockMetrics
        // 要求 height > 0），不得像過去的 bug 那樣被頂成一整個 pixel。
        final midMetrics = result.store.get(result.namespace, group[1].key)!;
        expect(midMetrics.height, greaterThan(0));
        expect(
          midMetrics.height,
          lessThan(0.01),
          reason: '同一行多切點的中間切塊視覺上不佔任何高度，不得累積人工像素',
        );
        expect(midMetrics.lineCount, 0);

        // 總高度仍必須等於連續排版 + trailingSpacing——不因中間切塊的極小
        // floor 值而系統性偏移；容差遠低於既有測試的 0.01，確保沒有整像素
        // 被誤加進去。
        var totalHeight = 0.0;
        for (final block in group) {
          totalHeight += result.store.get(result.namespace, block.key)!.height;
        }
        expect(
          totalHeight,
          closeTo(reference.height + trailingSpacing, 0.001),
        );

        // 切點之後的世界座標仍須與連續排版一致，不因中間切塊的極小 floor
        // 累積偏移量。
        final probeOffset = (line.end + 2).clamp(0, paragraphText.length - 1);
        final refY = lineTopForOffset(reference, probeOffset, paragraphText.length)!;
        final segY = worldYForOffset(
          group: group,
          cache: result.cache,
          store: result.store,
          namespace: result.namespace,
          chapterOffset: probeOffset,
        );
        expect(segY, closeTo(refY, 0.01));

        result.cache.dispose();
      },
    );
  });
}
