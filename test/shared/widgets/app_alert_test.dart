import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/clause_text.dart';

Future<void> _open(
  WidgetTester tester,
  void Function(BuildContext context) open, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(AppStyle.kraft, brightness),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => open(context),
            child: const Text('開'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('開'));
  await tester.pumpAndSettle();
}

/// 提示框裡每一段字的字級（圖示也是一段字）。
Set<double> _fontSizes(WidgetTester tester) {
  final sizes = <double>{};
  for (final element
      in find
          .descendant(
            of: find.byType(AppAlert<bool>),
            matching: find.byWidgetPredicate((w) => w is RichText),
          )
          .evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final text = paragraph.text;
    void visit(InlineSpan span, double? inherited) {
      final size = span.style?.fontSize ?? inherited;
      if (span is TextSpan) {
        if ((span.text ?? '').trim().isNotEmpty) sizes.add(size!);
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child, size);
        }
      }
    }

    visit(text, null);
  }
  return sizes;
}

void main() {
  testWidgets('提示框只有兩種字級：標題與按鈕 17，其餘 15', (tester) async {
    await _open(
      tester,
      (context) => showAppConfirm(
        context: context,
        title: '刪除 3 本書？',
        message: '下載的章節與封面一起刪除。',
        irreversible: true,
        content: AlertTextField(
          controller: TextEditingController(),
          errorText: '請輸入名稱',
        ),
        confirmLabel: '刪除',
        destructive: true,
      ),
    );
    expect(_fontSizes(tester), {17.0, 15.0});
    expect(find.text('無法復原'), findsOneWidget);
  });

  testWidgets('不是無法復原的提示不畫那一行', (tester) async {
    await _open(
      tester,
      (context) => showAppConfirm(
        context: context,
        title: '清除網頁資料？',
        message: '要登入的書源得重新驗證。',
      ),
    );
    expect(find.text('無法復原'), findsNothing);
  });

  testWidgets('說明是正常濃度的字色', (tester) async {
    for (final brightness in Brightness.values) {
      await _open(
        tester,
        (context) => showAppConfirm(
          context: context,
          title: '清除日誌？',
          message: '清除後就沒有了。',
        ),
        brightness: brightness,
      );
      final message = tester.widget<Text>(find.text('清除後就沒有了。'));
      final scheme = Theme.of(tester.element(find.text('清除後就沒有了。')))
          .colorScheme;
      expect(message.style!.color, scheme.onSurface);
      Navigator.of(tester.element(find.text('清除後就沒有了。'))).pop();
      await tester.pumpAndSettle();
    }
  });

  group('說明照子句換行', () {
    // 測試字型每個字都是一個字級寬：寬 10 個字。
    const style = TextStyle(fontSize: 10);
    String wrap(String text) => ClauseText.wrapClauses(
      text,
      TextPainter(textDirection: TextDirection.ltr),
      style,
      100,
    );

    test('斷點前八個字內有逗號時，在逗號後斷', () {
      expect(wrap('甲乙丙丁戊，己庚辛壬癸子丑寅'), '甲乙丙丁戊，\n己庚辛壬癸子丑寅');
    });

    test('標點後面的收引號跟著上一行', () {
      expect(wrap('甲乙「丙丁。」戊己庚辛壬癸子'), '甲乙「丙丁。」\n戊己庚辛壬癸子');
    });

    test('沒有標點、最後只剩一兩個字時，往前多帶兩個字', () {
      expect(wrap('甲乙丙丁戊己庚辛壬癸子'), '甲乙丙丁戊己庚辛\n壬癸子');
    });

    test('最後一行前面是表情符號時不往前帶，不會切壞', () {
      // 寬 6 個字：第一行排到「戊」，只剩「己」。「😀」是兩個 UTF-16
      // 單位，往前帶兩個單位會切在它中間。
      final wrapped = ClauseText.wrapClauses(
        '甲乙丙丁😀戊己',
        TextPainter(textDirection: TextDirection.ltr),
        style,
        60,
      );
      expect(wrapped.replaceAll('\n', ''), '甲乙丙丁😀戊己');
      for (final line in wrapped.split('\n')) {
        final last = line.codeUnitAt(line.length - 1);
        expect(last >= 0xD800 && last <= 0xDBFF, isFalse, reason: '行尾是半個字');
      }
    });

    test('一行排得下就不動，原本的換行照留', () {
      expect(wrap('甲乙丙'), '甲乙丙');
      expect(wrap('甲乙\n丙丁'), '甲乙\n丙丁');
    });
  });
}
