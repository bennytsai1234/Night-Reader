import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

import 'reader_v2_state_transition_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ChineseUtils.initialize);

  const text = '第一句保留。第二句也在這裡。第三句是另一個位置。';

  test('位置跑到另一句時，anchor assertion 會失敗並帶出兩邊實際文字', () {
    final before = ReaderAnchorProbe.capture(
      location: const ReaderV2Location(chapterIndex: 2, charOffset: 0),
      sourceText: text,
    );
    final after = ReaderAnchorProbe.capture(
      location: ReaderV2Location(
        chapterIndex: 2,
        charOffset: text.indexOf('第三句'),
      ),
      sourceText: text,
    );

    expect(
      () => expectReaderAnchorPreserved(before, after),
      throwsA(
        isA<ReaderAnchorMismatch>()
            .having((error) => error.before.anchorText, 'before', '第一句保留。')
            .having((error) => error.after.anchorText, 'after', '第三句是另一個位置。'),
      ),
    );
  });

  test('同一句的 offset 改變時，exact anchor assertion 不會誤報', () {
    final before = ReaderAnchorProbe.capture(
      location: const ReaderV2Location(chapterIndex: 2, charOffset: 0),
      sourceText: text,
    );
    final after = ReaderAnchorProbe.capture(
      location: ReaderV2Location(
        chapterIndex: 2,
        charOffset: text.indexOf('保留'),
      ),
      sourceText: text,
    );

    expectReaderAnchorPreserved(before, after);
  });

  test('簡繁等價模式會正規化兩邊文字，而 exact 模式仍會抓到差異', () {
    final before = ReaderAnchorProbe.capture(
      location: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      sourceText: '讀者閱讀測試。',
    );
    final after = ReaderAnchorProbe.capture(
      location: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      sourceText: '读者阅读测试。',
    );

    expect(
      () => expectReaderAnchorPreserved(before, after),
      throwsA(isA<ReaderAnchorMismatch>()),
    );
    expectReaderAnchorPreserved(
      before,
      after,
      mode: ReaderAnchorComparisonMode.equivalentText,
      equivalentConversionType: 1,
    );
  });

  test('generation、epoch 與 metrics freshness helpers 同時涵蓋正反例', () {
    expectReaderLayoutGenerationAdvanced(4, 5);
    expectReaderEpochAlignedWithGeneration(epoch: 5, layoutGeneration: 5);
    expectReaderMetricsFreshForSignature(
      currentSignature: 42,
      observedSignatures: <int>[42, 42],
    );

    expect(
      () => expectReaderLayoutGenerationAdvanced(4, 4),
      throwsA(isA<StateError>()),
    );
    expect(
      () =>
          expectReaderEpochAlignedWithGeneration(epoch: 4, layoutGeneration: 5),
      throwsA(isA<StateError>()),
    );
    expect(
      () => expectReaderMetricsFreshForSignature(
        currentSignature: 42,
        observedSignatures: <int>[41, 42],
      ),
      throwsA(isA<StateError>()),
    );
  });
}
