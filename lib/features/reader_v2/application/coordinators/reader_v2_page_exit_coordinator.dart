import 'package:flutter/material.dart';
import 'package:reader/core/models/book.dart';

typedef ReaderV2ExitPrompt =
    Future<bool?> Function(BuildContext context, Book book);

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
    required bool Function() isDrawerOpen,
    required VoidCallback popNavigator,
  }) async {
    if (_isHandlingExit || !context.mounted) return;
    if (isDrawerOpen()) {
      popNavigator();
      return;
    }

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

      final addToBookshelf = await _promptAddToBookshelf(
        context,
        provider.book,
      );
      if (!context.mounted) return;
      if (addToBookshelf == true) {
        await provider.addCurrentBookToBookshelf();
        if (!context.mounted) return;
      } else {
        await provider.discardUnkeptBookStorage();
        if (!context.mounted) return;
      }
      popNavigator();
    } finally {
      _isHandlingExit = false;
    }
  }

  static Future<bool?> _showAddToBookshelfDialog(
    BuildContext context,
    Book book,
  ) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            title: const Text('加入書架？'),
            content: Text('《${book.name}》尚未加入書架，是否在退出前加入書架以保留目前閱讀進度？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('直接退出'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('加入書架'),
              ),
            ],
          ),
    );
  }
}
