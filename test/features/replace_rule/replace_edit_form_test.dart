import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
