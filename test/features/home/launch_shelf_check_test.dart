// 開 App 進場播完後，書架讀完才開始檢查書架更新（ADR 0018、0029）。等的是
// 讀取本身做完，不是書架的通知：書架重讀時讀回來的書沒變就不通知，等通知
// 的話這一次檢查永遠不會開始。整個 App（記憶體資料庫）跑一次。

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/app_providers.dart';
import 'package:night_reader/core/config/app_config.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/main.dart';
import 'package:provider/provider.dart';

import '../../support/app_harness.dart';

/// 下一次讀書架要等 [gate] 放行。
class _GatedBookDao extends BookDao {
  _GatedBookDao(super.db);

  Completer<void>? gate;

  @override
  Future<List<Book>> getInBookshelf() async {
    final waiting = gate;
    if (waiting != null) {
      gate = null;
      await waiting.future;
    }
    return super.getInBookshelf();
  }
}

void main() {
  testWidgets('the launch shelf check starts even when a reload that changes '
      'nothing is still reading as the entrance ends', (tester) async {
    setUpPhone(tester);
    AppConfig.autoRefresh = true;
    late _GatedBookDao dao;
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary(withContent: false);
      dao = _GatedBookDao(getIt<AppDatabase>());
      getIt
        ..unregister<BookDao>()
        ..registerSingleton<BookDao>(dao);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: AppProviders.providers,
        child: const ReaderApp(),
      ),
    );
    // 書讀到了、骨架還在呼吸時，下載完成之類的原因又要重讀一次書架，這一次
    // 讀得慢，進場播完時還沒讀完。
    await settle(tester, const Duration(milliseconds: 700));
    final provider = tester
        .element(find.byType(BookshelfPage))
        .read<BookshelfProvider>();
    var checked = false;
    void onChecking() => checked |= provider.checkingShelf.value;
    provider.checkingShelf.addListener(onChecking);
    addTearDown(() => provider.checkingShelf.removeListener(onChecking));
    final gate = dao.gate = Completer<void>();
    AppEventBus().fire(AppEventBus.upBookshelf, data: kBookUrl);

    // 進場播完（骨架長出、停頓、收住呼吸、換場），開 App 的背景工作開始等
    // 書架讀完。
    await settle(tester, const Duration(seconds: 5));
    expect(checked, isFalse, reason: '書架還沒讀完，先不檢查');

    // 讀完了，書架沒有變：不通知，但檢查照樣開始。
    gate.complete();
    await settle(tester, const Duration(seconds: 2));
    expect(checked, isTrue, reason: '書架讀完就開始檢查更新');

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester, const Duration(seconds: 3));
    await tester.pump(const Duration(minutes: 1));
  });
}
