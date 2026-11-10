import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';

import '../import_content.dart';

/// AssociationHandlerService 的基礎狀態與生命週期定義
abstract class AssociationBase {
  late AppLinks appLinks;
  StreamSubscription? linkSubscription;
  StreamSubscription? sharedMediaSubscription;

  void init(
    BuildContext context, {
    required Function(BuildContext, Uri) onUri,
    required Function(BuildContext, List<dynamic>) onMedia,
  });

  /// 連結已經寫明類型（`legado://import/bookSource`、
  /// `yuedu://booksource/importonline`）時直接問要不要匯入，按下才下載。
  void showLinkImportDialog(
    BuildContext context,
    ImportContentKind kind,
    String url,
  );

  /// 沒寫類型的連結：先下載內容，再照 [detectImportContentKind] 判斷。
  Future<void> importUntypedLink(BuildContext context, String url);

  /// 已經拿到內容（分享的檔案或文字）：照 [detectImportContentKind] 判斷。
  /// [label] 是對話框裡指稱這份內容的名字，例如檔名。
  void importContent(BuildContext context, String label, String text);

  void dispose() {
    linkSubscription?.cancel();
    sharedMediaSubscription?.cancel();
  }
}
