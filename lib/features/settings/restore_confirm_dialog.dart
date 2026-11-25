import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/lists/grouped_row.dart';
import 'package:night_reader/shared/widgets/popups/app_dialogs.dart';

/// 從備份檔還原前的確認框：「設定也還原」開關預設開，關掉時設定保留這台
/// 的、資料照樣還原（`RestoreService.restoreFromZip` 的 `restoreSettings`）。
/// 按「開始還原」回傳開關的狀態，取消或點外面回傳 null。
Future<({bool restoreSettings})?> confirmRestore(BuildContext context) async {
  var restoreSettings = true;
  final confirmed = await showStatefulAppAlert<bool>(
    context: context,
    builder: (context, setState, _) => AppAlert<bool>(
      title: '還原這份備份？',
      message: '備份裡的資料併進目前的，相同的項目以備份為準。',
      content: AlertGroupedCard(
        rows: [
          GroupedSwitchRow(
            title: '設定也還原',
            value: restoreSettings,
            onChanged: (value) => setState(() => restoreSettings = value),
          ),
        ],
      ),
      actions: const [
        AppAlertAction(label: '取消', value: false),
        AppAlertAction(label: '開始還原', value: true, isDefault: true),
      ],
    ),
  );
  return confirmed == true ? (restoreSettings: restoreSettings) : null;
}
