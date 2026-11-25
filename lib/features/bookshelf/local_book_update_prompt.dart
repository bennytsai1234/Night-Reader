import 'package:flutter/widgets.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/shared/widgets/popups/app_dialogs.dart';

/// 加入的本地書和書架上的 [existing] 同名、同格式、內容不同（多半是連載
/// 下載的新版）時，問要更新那本還是另加一本；關掉提示框算另加一本。
Future<bool> askLocalBookUpdate(BuildContext context, Book existing) async {
  if (!context.mounted) return false;
  final update = await showAppAlert<bool>(
    context: context,
    title: '更新《${existing.name}》？',
    message:
        '書架上已經有同名的書（作者：${existing.author}）。'
        '更新會換成這次選的檔、重新分章，閱讀進度、書籤與標註留著。',
    actions: const [
      AppAlertAction(label: '更新', value: true, isDefault: true),
      AppAlertAction(label: '另加一本', value: false),
    ],
  );
  return update ?? false;
}
