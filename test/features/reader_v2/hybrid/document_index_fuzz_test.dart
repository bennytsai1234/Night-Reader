import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/document_index.dart';

/// 增量 DocumentIndex 對照樸素參考模型的隨機化等價性驗證。
/// 覆蓋：亂數高度、亂數 center、雙側交錯放行、topOf/bottomOf/
/// blockAtOffset/keysInRange/chapterRange/chapterExtent/edge keys。
void main() {
  test('DocumentIndex 隨機交錯放行下與樸素模型全等', () {
    final random = Random(20260710);
    for (var round = 0; round < 30; round += 1) {
      final chapterCount = 1 + random.nextInt(6);
      final blocksPerChapter = List<int>.generate(
        chapterCount,
        (_) => 1 + random.nextInt(9),
      );
      final allKeys = <BlockKey>[
        for (var c = 0; c < chapterCount; c += 1)
          for (var b = 0; b < blocksPerChapter[c]; b += 1)
            BlockKey(chapterIndex: c, blockIndex: b),
      ];
      final heights = <BlockKey, double>{
        for (final key in allKeys) key: 5.0 + random.nextDouble() * 200.0,
      };
      final centerPos = random.nextInt(allKeys.length);
      final center = allKeys[centerPos];
      final index = DocumentIndex(centerKey: center);

      // 由 center 向兩側隨機交錯放行（模擬 admission 的實際順序）。
      var forward = centerPos;
      var backward = centerPos - 1;
      final admitted = <BlockKey>[];
      while (forward < allKeys.length || backward >= 0) {
        final goForward =
            backward < 0 ||
            (forward < allKeys.length && random.nextBool());
        if (goForward) {
          index.admit(
            allKeys[forward],
            BlockMetrics(height: heights[allKeys[forward]]!, lineCount: 1),
          );
          admitted.add(allKeys[forward]);
          forward += 1;
        } else {
          index.admit(
            allKeys[backward],
            BlockMetrics(height: heights[allKeys[backward]]!, lineCount: 1),
          );
          admitted.add(allKeys[backward]);
          backward -= 1;
        }

        // 每次放行後即時對照——增量結構任何一步走樣都會在此暴露。
        final sorted = admitted.toList()..sort();
        // 樸素座標：center 的 top 恆為 0，向兩側累加高度。
        // center 可能尚未放行（backward 先行），以「小於 center 的鍵數」定位。
        final tops = <BlockKey, double>{};
        final centerSortedPos = sorted.where((k) => k < center).length;
        var cursor = 0.0;
        for (var i = centerSortedPos; i < sorted.length; i += 1) {
          tops[sorted[i]] = cursor;
          cursor += heights[sorted[i]]!;
        }
        final afterTotal = cursor;
        cursor = 0.0;
        for (var i = centerSortedPos - 1; i >= 0; i -= 1) {
          cursor -= heights[sorted[i]]!;
          tops[sorted[i]] = cursor;
        }
        final beforeTotal = -cursor;

        expect(index.keys.toList(), sorted);
        expect(index.beforeExtent, closeTo(beforeTotal, 1e-6));
        expect(index.afterExtent, closeTo(afterTotal, 1e-6));
        expect(index.backwardEdgeKey, centerSortedPos == 0 ? null : sorted.first);
        expect(
          index.forwardEdgeKey,
          centerSortedPos == sorted.length ? null : sorted.last,
        );
        for (final key in sorted) {
          expect(index.topOf(key), closeTo(tops[key]!, 1e-6), reason: '$key');
          expect(
            index.bottomOf(key),
            closeTo(tops[key]! + heights[key]!, 1e-6),
          );
        }

        // blockAtOffset：對每個 block 的內部點與邊界點抽查。
        for (var probe = 0; probe < 8; probe += 1) {
          final offset =
              -beforeTotal - 10 +
              random.nextDouble() * (beforeTotal + afterTotal + 20);
          BlockKey? expected;
          for (final key in sorted) {
            final top = tops[key]!;
            if (offset >= top && offset < top + heights[key]!) {
              expected = key;
              break;
            }
          }
          expect(
            index.blockAtOffset(offset),
            expected,
            reason: 'offset=$offset round=$round n=${sorted.length}',
          );
        }

        // keysInRange 對照。
        for (var probe = 0; probe < 4; probe += 1) {
          final a =
              -beforeTotal - 20 +
              random.nextDouble() * (beforeTotal + afterTotal + 40);
          final b = a + random.nextDouble() * 300;
          final expected = sorted.where((key) {
            final top = tops[key]!;
            return top + heights[key]! > a && top < b;
          }).toList();
          expect(index.keysInRange(a, b), expected, reason: '[$a, $b)');
        }
      }

      // 全部放行後的章節範圍對照。
      for (var c = 0; c < chapterCount; c += 1) {
        final chapterKeys =
            allKeys.where((key) => key.chapterIndex == c).toList();
        final sorted = admitted.toList()..sort();
        final tops = <BlockKey, double>{};
        final centerSortedPos = sorted.where((k) => k < center).length;
        var cursor = 0.0;
        for (var i = centerSortedPos; i < sorted.length; i += 1) {
          tops[sorted[i]] = cursor;
          cursor += heights[sorted[i]]!;
        }
        cursor = 0.0;
        for (var i = centerSortedPos - 1; i >= 0; i -= 1) {
          cursor -= heights[sorted[i]]!;
          tops[sorted[i]] = cursor;
        }
        final expectedTop = tops[chapterKeys.first]!;
        final expectedBottom =
            tops[chapterKeys.last]! + heights[chapterKeys.last]!;
        final range = index.chapterRange(c)!;
        expect(range.top, closeTo(expectedTop, 1e-6), reason: 'chapter $c');
        expect(range.bottom, closeTo(expectedBottom, 1e-6));
        expect(
          index.chapterExtent(c),
          closeTo(expectedBottom - expectedTop, 1e-6),
        );
      }
    }
  });
}
