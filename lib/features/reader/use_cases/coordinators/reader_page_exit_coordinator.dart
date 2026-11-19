import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/shared/widgets/popups/app_dialogs.dart';

/// 「加入書架？」的選擇；沒選（按取消、點框外、返回鍵）是 null，留在閱讀器。
enum ReaderExitChoice { addToBookshelf, leave }

typedef ReaderExitPrompt = Future<ReaderExitChoice?> Function(
  BuildContext context,
  Book book,
);

abstract class ReaderExitFlowDelegate {
  Book get book;

  bool shouldPromptAddToBookshelfOnExit();

  Future<void> persistExitProgress();

  Future<void> addCurrentBookToBookshelf();

  Future<void> discardUnkeptBookStorage();
}

class ReaderPageExitCoordinator {
  ReaderPageExitCoordinator({ReaderExitPrompt? promptAddToBookshelf})
    : _promptAddToBookshelf = promptAddToBookshelf ?? _showAddToBookshelfDialog;

  final ReaderExitPrompt _promptAddToBookshelf;
  bool _isHandlingExit = false;

  Future<void> handleExitIntent({
    required BuildContext context,
    required ReaderExitFlowDelegate provider,
    required VoidCallback popNavigator,
  }) async {
    if (_isHandlingExit || !context.mounted) return;

    _isHandlingExit = true;
    try {
      final shouldPrompt = provider.shouldPromptAddToBookshelfOnExit();
      await provider.persistExitProgress();
      if (!context.mounted) return;
      if (!shouldPrompt) {
        if (!provider.book.isInBookshelf) {
          await provider.discardUnkeptBookStorage();
          if (!context.mounted) return;
        }
        popNavigator();
        return;
      }

      final choice = await _promptAddToBookshelf(context, provider.book);
      if (!context.mounted) return;
      switch (choice) {
        case null:
          return;
        case ReaderExitChoice.addToBookshelf:
          await provider.addCurrentBookToBookshelf();
        case ReaderExitChoice.leave:
          await provider.discardUnkeptBookStorage();
      }
      if (!context.mounted) return;
      popNavigator();
    } finally {
      _isHandlingExit = false;
    }
  }

  /// 三顆按鈕直排：加入書架、直接退出、取消（留在閱讀器）。
  static Future<ReaderExitChoice?> _showAddToBookshelfDialog(
    BuildContext context,
    Book book,
  ) {
    return showAppAlert<ReaderExitChoice?>(
      context: context,
      title: '把《${book.name}》加入書架？',
      message: '加入書架才會留下這次的閱讀進度。',
      actions: const [
        AppAlertAction(
          label: '加入書架',
          value: ReaderExitChoice.addToBookshelf,
          isDefault: true,
        ),
        AppAlertAction(label: '直接退出', value: ReaderExitChoice.leave),
        AppAlertAction(label: '取消', value: null),
      ],
    );
  }
}
