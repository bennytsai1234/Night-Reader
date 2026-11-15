import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/core/services/ui_language.dart';
import 'package:night_reader/shared/widgets/ui_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    ChineseUtils.initializeFromDictionaryData([
      '',
      '',
      '',
      '書\t书\n架\t架\n搜\t搜\n尋\t寻\n設\t设\n定\t定\n',
    ]);
  });

  test('繁簡預設依系統語言判斷，非中文保持繁體', () {
    expect(prefersSimplified(const Locale('zh', 'CN')), isTrue);
    expect(prefersSimplified(const Locale('zh', 'SG')), isTrue);
    expect(
      prefersSimplified(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      ),
      isTrue,
    );
    expect(prefersSimplified(const Locale('zh', 'TW')), isFalse);
    expect(prefersSimplified(const Locale('zh', 'HK')), isFalse);
    expect(
      prefersSimplified(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ),
      isFalse,
    );
    expect(prefersSimplified(const Locale('en', 'US')), isFalse);
  });

  testWidgets('介面字串隨選擇切換，沒有更改原文', (tester) async {
    Widget app(Locale locale) => MaterialApp(
      home: UiLanguageScope(
        locale: locale,
        child: const Scaffold(body: UiText('書架 搜尋')),
      ),
    );
    await tester.pumpWidget(app(const Locale('zh', 'TW')));
    expect(find.text('書架 搜尋'), findsOneWidget);
    await tester.pumpWidget(app(const Locale('zh', 'CN')));
    expect(find.text('书架 搜寻'), findsOneWidget);
    await tester.pumpWidget(app(const Locale('zh', 'TW')));
    expect(find.text('書架 搜尋'), findsOneWidget);
  });

  testWidgets('資料文字可選擇不跟介面語言轉換', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UiLanguageScope(
          locale: const Locale('zh', 'CN'),
          child: const Scaffold(body: UiText('書架', translate: false)),
        ),
      ),
    );
    expect(find.text('書架'), findsOneWidget);
  });
}
