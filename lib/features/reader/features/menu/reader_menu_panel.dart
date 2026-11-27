import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';

/// 從閱讀選單開面板（`docs/design/reader.md`「面板」）：開著時上下選單與
/// 亮度條收起（[hideMenu]），正文整頁露出來；面板關掉、閱讀器仍是最上面
/// 那一頁時回到選單打開的樣子（[showMenu]）。文字閱讀器與漫畫閱讀器共用。
///
/// 選單從面板滑上來的下一格才開始滑出：面板的第一格要建整個面板的骨架，
/// 選單開始滑出那一格要重算整組選單的讀屏資訊，兩件事錯開一格（ADR 0029
/// 做法 4；擠在同一格時那一格多 1–2ms）。
void openReaderMenuPanel(
  BuildContext context, {
  required Future<void> Function() open,
  required VoidCallback hideMenu,
  required VoidCallback showMenu,
}) {
  var closed = false;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted && !closed) hideMenu();
  });
  WidgetsBinding.instance.ensureVisualUpdate();
  unawaited(
    open().whenComplete(() {
      closed = true;
      if (!context.mounted || !(pageRouteOf(context)?.isCurrent ?? false)) {
        return;
      }
      showMenu();
    }),
  );
}
