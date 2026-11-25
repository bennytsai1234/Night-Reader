import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/shared/widgets/popups/app_dialogs.dart';

/// 「搜尋目錄」提示框（書籍詳情與閱讀器的目錄共用）：一個輸入框，打字時
/// 就交給 [onChanged] 篩目錄（[tocTitleMatches]），「關閉」收起、搜尋留著。
/// [initial] 是目前的搜尋字。
Future<void> showTocSearchDialog(
  BuildContext context, {
  required String initial,
  required ValueChanged<String> onChanged,
}) => showStatefulAppAlert<void>(
  context: context,
  fieldTexts: [initial],
  builder: (ctx, _, fields) => AppAlert<void>(
    title: '搜尋目錄',
    content: AlertGroupedCard(
      rows: [
        GroupedTextFieldRow(
          controller: fields.single,
          autofocus: true,
          onChanged: onChanged,
        ),
      ],
    ),
    actions: const [AppAlertAction(label: '關閉', value: null, isDefault: true)],
  ),
);
