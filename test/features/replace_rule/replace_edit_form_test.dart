import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/chinese/chinese_utils.dart';
import 'package:night_reader/core/chinese/ui_language.dart';
import 'package:night_reader/features/replace_rule/widgets/replace_edit_form.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

void main() {
  testWidgets('a pattern made only of full-width spaces is valid', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    final controllers = List.generate(5, (_) => TextEditingController());
    addTearDown(() {
      for (final c in controllers) {
        c.dispose();
      }
    });
    controllers[0].text = '移除縮排';
    controllers[3].text = '　　';

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: ReplaceEditForm(
                nameCtrl: controllers[0],
                groupCtrl: controllers[1],
                timeoutCtrl: controllers[2],
                patternCtrl: controllers[3],
                replacementCtrl: controllers[4],
              ),
            ),
          ),
        ),
      ),
    );

    expect(formKey.currentState!.validate(), isTrue);

    controllers[3].text = '';
    expect(formKey.currentState!.validate(), isFalse);
  });

  testWidgets('簡體介面：兩個空欄位的錯誤跟著轉成簡體', (tester) async {
    ChineseUtils.initializeFromDictionaryData([
      '',
      '',
      '',
      '稱\t称\n為\t为\n則\t则\n內\t内\n',
    ]);
    UiLanguageText.clearCache();
    final formKey = GlobalKey<FormState>();
    final controllers = List.generate(5, (_) => TextEditingController());
    addTearDown(() {
      for (final c in controllers) {
        c.dispose();
      }
    });

    await tester.pumpWidget(
      UiLanguageScope(
        locale: const Locale('zh', 'CN'),
        child: MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: ReplaceEditForm(
                  nameCtrl: controllers[0],
                  groupCtrl: controllers[1],
                  timeoutCtrl: controllers[2],
                  patternCtrl: controllers[3],
                  replacementCtrl: controllers[4],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('名称不能为空'), findsOneWidget);
    expect(find.text('正则内容不能为空'), findsOneWidget);
  });
}
