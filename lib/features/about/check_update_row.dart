import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/grouped_list_skeleton.dart';

import 'update_check_runner.dart';

/// 「檢查更新」一列：點了手動檢查，檢查中顯示「檢查中…」與轉圈，結果用
/// 提示訊息說（有新版時跳更新視窗）。放在「我的」第一層（ADR 0030）。
class CheckUpdateRow extends StatefulWidget
    implements GroupedRowLike, GroupedSkeletonItem {
  const CheckUpdateRow({super.key});

  @override
  bool get hasLeading => true;

  /// [checking] 時右側寫「檢查中…」並轉圈。
  static GroupedRow _row({required bool checking, VoidCallback? onTap}) =>
      GroupedRow(
        leading: const GroupedIconTile(
          Icons.system_update_alt_rounded,
          tint: AppTint.moss,
        ),
        title: '檢查更新',
        // 目前版本寫在「關於夜讀」頁頂，這裡只在檢查時顯示狀態。
        value: checking ? '檢查中…' : null,
        trailing: checking
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        showChevron: !checking,
        onTap: onTap,
      );

  /// 推入時這一列剛建好，還沒在檢查。
  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) =>
      _row(checking: false, onTap: () {}).skeletonShape(context, width: width);

  @override
  State<CheckUpdateRow> createState() => _CheckUpdateRowState();
}

class _CheckUpdateRowState extends State<CheckUpdateRow> {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    final outcome = await UpdateCheckRunner().runManual(context);
    if (!mounted) return;
    setState(() => _checking = false);
    final message = switch (outcome) {
      UpdateCheckOutcome.shown => null,
      UpdateCheckOutcome.upToDate => '已是最新版',
      UpdateCheckOutcome.failed => '檢查更新失敗，請稍後再試',
      UpdateCheckOutcome.dismissed => null,
      UpdateCheckOutcome.notSupported => '目前平台不支援自動更新',
    };
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) =>
      CheckUpdateRow._row(checking: _checking, onTap: _check);
}
