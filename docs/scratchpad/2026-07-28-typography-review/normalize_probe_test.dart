// 診斷用 probe：把常見網文樣本丟進 normalizeTypography，印出前後對照，
// 用來檢查引號／括號／英數／標題的轉換結果是否符合預期。
// 執行：flutter test docs/scratchpad/2026-07-28-typography-review/normalize_probe_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content_transformer.dart';

void main() {
  const samples = <String>[
    '他說“你好”，然後轉身離開。',
    '“你確定嗎？”她問，“這可不是小事。”',
    '【系統提示】你已獲得 3 點經驗值。',
    '〖任務〗擊敗 Boss（限時 24 小時）',
    '這本書叫《魔戒》，作者是 J.R.R. Tolkien。',
    '他打開 iPhone 15 Pro，看到 CEO 發來的 email。',
    '溫度是 36.5 度，時間是 2026/07/28 15:30。',
    '「他說『我不去』」，這是巢狀引號。',
    '他喊道:"住手!"，聲音很大.',
    '哈利·波特與 Dr. Watson 的對話…',
    '第一章 起點 (上)',
    '第 12 章 The Beginning',
    r'價格是 $100 USD，約 NT$3,200 元。',
    '他說--不，是他喊——「快跑！」',
    '這是 100% 的 CPU 使用率 [警告]。',
  ];

  test('normalizeTypography 對照輸出（內文）', () {
    for (final sample in samples) {
      final out = normalizeTypography(sample);
      // ignore: avoid_print
      print('IN : $sample\nOUT: $out\n');
    }
  });

  test('normalizeTypography 對照輸出（標題，preserveCjkSpaces）', () {
    const titles = <String>[
      '第一章 起點 (上)',
      '第 12 章 The Beginning',
      '【第三卷】風起 [完]',
      '第五章 “初遇”',
    ];
    for (final title in titles) {
      final out = normalizeTypography(title, preserveCjkSpaces: true);
      // ignore: avoid_print
      print('TITLE IN : $title\nTITLE OUT: $out\n');
    }
  });
}
