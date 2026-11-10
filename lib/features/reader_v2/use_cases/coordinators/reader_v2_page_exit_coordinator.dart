import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';

/// 「加入書架？」的選擇；沒選（按取消、點框外、返回鍵）是 null，留在閱讀器。
enum ReaderV2ExitChoice { addToBookshelf, leave }

typedef ReaderV2ExitPrompt = Future<ReaderV2ExitChoice?> Function(
  BuildContext context,
  Book book,
);

abstract class ReaderV2ExitFlowDelegate {
  Book get book;

  bool shouldPromptAddToBookshelfOnExit();

  Future<void> persistExitProgress();

  Future<void> addCurrentBookToBookshelf();

  Future<void> discardUnkeptBookStorage();
}

class ReaderV2PageExitCoordinator {
  ReaderV2PageExitCoordinator({ReaderV2ExitPrompt? promptAddToBookshelf})
    : _promptAddToBookshelf = promptAddToBookshelf ?? _showAddToBookshelfDialog;

  final ReaderV2ExitPrompt _promptAddToBookshelf;
  bool _isHandlingExit = false;

  Future<void> handleExitIntent({
    required BuildContext context,
    required ReaderV2ExitFlowDelegate provider,
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
        case ReaderV2ExitChoice.addToBookshelf:
          await provider.addCurrentBookToBookshelf();
        case ReaderV2ExitChoice.leave:
          await provider.discardUnkeptBookStorage();
      }
      if (!context.mounted) return;
      popNavigator();
    } finally {
      _isHandlingExit = false;
    }
  }

  /// 三顆按鈕直排：加入書架、直接退出、取消（留在閱讀器）。
  static Future<ReaderV2ExitChoice?> _showAddToBookshelfDialog(
    BuildContext context,
    Book book,
  ) {
    return showAppAlert<ReaderV2ExitChoice?>(
      context: context,
      title: '加入書架？',
      message: '《${book.name}》尚未加入書架，是否在退出前加入書架以保留目前閱讀進度？',
      actions: const [
        AppAlertAction(
          label: '加入書架',
          value: ReaderV2ExitChoice.addToBookshelf,
          isDefault: true,
        ),
        AppAlertAction(label: '直接退出', value: ReaderV2ExitChoice.leave),
        AppAlertAction(label: '取消', value: null),
      ],
    );
  }
}
