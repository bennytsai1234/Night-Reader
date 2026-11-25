import 'dart:async';

import 'package:dio/dio.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:provider/provider.dart';

import '../import_content.dart';
import 'association_base.dart';

import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/features/replace_rule/widgets/replace_rule_import_sheet.dart';
import 'package:night_reader/core/backup/bookshelf_exchange_service.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/source/book_link_service.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/settings/sync_status_text.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';
import 'package:night_reader/features/source_manager/widgets/import_preview_sheet.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/shared/widgets/popups/app_dialogs.dart';

/// AssociationHandlerService 的對話框與 UI 邏輯擴展
mixin AssociationDialogHelper on AssociationBase {
  /// 加入書架的連結找書用的（測試換成假的書源）。
  @visibleForTesting
  BookLinkService Function() bookLinks = BookLinkService.new;

  /// 打開找到的書的書籍詳情（測試換成記下開了哪本）。
  @visibleForTesting
  Future<void> Function(BuildContext context, Book book) openBookDetail =
      openBookDetailPage;

  /// 找書時開一個點外面關不掉的進度框，可以按「取消」或返回鍵收掉；收掉
  /// （含進度框被拿掉）就停掉正在抓的請求，什麼都不提示。
  @override
  Future<void> addBookFromLink(BuildContext context, String url) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final cancel = CancelToken();
    Route<void>? progress;
    final dialog = showStatefulAppAlert<void>(
      context: context,
      barrierDismissible: false,
      builder: (context, _, _) {
        progress ??= ModalRoute.of(context);
        return _CancelOnDispose(
          cancelToken: cancel,
          child: const AppAlert<bool>(
            title: '加入書架',
            content: SyncProgressView(value: null, label: '正在找書…'),
            actions: [AppAlertAction(label: '取消', value: true)],
          ),
        );
      },
    );
    unawaited(dialog.whenComplete(cancel.cancel));

    Book? book;
    Object? failure;
    StackTrace? failureStack;
    try {
      book = await bookLinks().findBook(url, cancelToken: cancel);
    } catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    }
    if (cancel.isCancelled) return;
    // 收掉自己這個進度框：又點了一條連結時，上面可能疊著另一個。還沒畫出
    // 第一幀就找完時拿不到它，照最上面的收。
    final route = progress;
    if (route == null || route.isCurrent) {
      navigator.pop();
      await dialog;
    } else if (route.isActive) {
      navigator.removeRoute(route);
    }
    if (!context.mounted) return;
    if (book == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: UiText(switch (failure) {
            BookAlreadyOnShelfException(:final message) => message,
            _ => failureMessage('加入書架', failure!, failureStack),
          }),
        ),
      );
      return;
    }
    // 同 Legado：直接開書籍詳情，讀者看過簡介、目錄再決定要不要加入書架。
    await openBookDetail(context, book);
  }

  @override
  void showLinkImportDialog(
    BuildContext context,
    ImportContentKind kind,
    String url,
  ) {
    unawaited(_runImportDialog(context, kind, url, url: url));
  }

  @override
  Future<void> importUntypedLink(BuildContext context, String url) async {
    final String text;
    try {
      text = await SourceImportService().fetchImportTextFromUrl(url);
    } catch (error, stackTrace) {
      final message = failureMessage('讀取匯入內容', error, stackTrace);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: UiText(message)));
      return;
    }
    if (!context.mounted) return;
    importContent(context, url, text);
  }

  @override
  void importContent(BuildContext context, String label, String text) {
    final kind = detectImportContentKind(text);
    if (kind == null) {
      showAppAlert<void>(
        context: context,
        title: '無法辨識',
        message: '「$label」不是夜讀能匯入的格式。',
        actions: const [
          AppAlertAction(label: '關閉', value: null, isDefault: true),
        ],
      );
      return;
    }
    unawaited(_runImportDialog(context, kind, label, text: text));
  }

  /// 問要不要匯入，按下後才匯入。[text] 是已經拿到的內容；沒有時（類型寫在
  /// 連結上）按下才從 [url] 下載。
  Future<void> _runImportDialog(
    BuildContext context,
    ImportContentKind kind,
    String label, {
    String? url,
    String? text,
  }) async {
    final action = switch (kind) {
      ImportContentKind.bookSource => '匯入書源',
      ImportContentKind.replaceRule => '匯入替換規則',
      ImportContentKind.bookshelf => '匯入書架',
      ImportContentKind.rssSource || ImportContentKind.theme => null,
    };
    final confirmed = await showAppAlert<bool>(
      context: context,
      title: '外部匯入',
      message: '偵測到外部內容：\n$label\n\n${kind.description}',
      actions: [
        if (action != null)
          AppAlertAction(label: action, value: true, isDefault: true),
        const AppAlertAction(label: '取消', value: false),
      ],
    );
    if (confirmed != true || action == null || !context.mounted) return;

    try {
      // 逐步呼叫會丟出原因的方法（網址、HTTP、JSON 錯誤），交給外層顯示
      // 「匯入書源失敗：原因」。
      final service = SourceImportService();
      final content = normalizeImportJson(
        text ?? await service.fetchImportTextFromUrl(url!),
      );
      final String message;
      switch (kind) {
        case ImportContentKind.bookSource:
          // 和書源管理同一段：開匯入預覽，這台改過、比檔案新的預設不覆蓋。
          if (!context.mounted) return;
          await importSourcesWithPreview(context, content, service: service);
          return;
        case ImportContentKind.bookshelf:
          final result = await BookshelfExchangeService().importFromText(
            content,
          );
          if (!context.mounted) return;
          await context.read<BookshelfProvider>().loadBooks();
          message = result.summary ?? '未找到可匯入的書架資料';
        case ImportContentKind.replaceRule:
          // 同書源：先開匯入預覽，這台已有的預設不勾。
          if (!context.mounted) return;
          await importReplaceRulesWithPreview(
            context,
            content,
            dao: getIt<ReplaceRuleDao>(),
          );
          return;
        case ImportContentKind.rssSource || ImportContentKind.theme:
          return;
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: UiText(message)));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: UiText(failureMessage(action, error))));
    }
  }
}
// AI_PORT: GAP-INTENT-01 extracted from AssociationHandlerService

/// 打開 [book] 的書籍詳情。
Future<void> openBookDetailPage(BuildContext context, Book book) =>
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => BookDetailPage(book: book)));

/// 進度框被拿掉時（例如底下的畫面整個收掉）取消 [cancelToken]。
class _CancelOnDispose extends StatefulWidget {
  const _CancelOnDispose({required this.cancelToken, required this.child});

  final CancelToken cancelToken;
  final Widget child;

  @override
  State<_CancelOnDispose> createState() => _CancelOnDisposeState();
}

class _CancelOnDisposeState extends State<_CancelOnDispose> {
  @override
  void dispose() {
    widget.cancelToken.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
