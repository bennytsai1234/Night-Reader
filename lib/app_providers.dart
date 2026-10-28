import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'core/di/injection.dart';
import 'core/services/download_service.dart';
import 'core/services/tts_service.dart';
import 'features/bookshelf/bookshelf_provider.dart';
import 'features/explore/explore_provider.dart';
import 'features/settings/settings_provider.dart';
import 'features/settings/theme_settings_provider.dart';

/// AppProviders - 集中管理全域 Provider
class AppProviders {
  static List<SingleChildWidget> get providers => [
    ChangeNotifierProvider(create: (_) => BookshelfProvider()),
    ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ChangeNotifierProvider(create: (_) => ThemeSettingsProvider()),
    // 單例不交給 Provider 管：用 create 的話整棵樹拆掉時會被 dispose，之後
    // 還在跑的下載一通知就出錯。
    ChangeNotifierProvider.value(value: DownloadService()),
    // TTSService 從 getIt 獲取單例，保持全域一致性
    ChangeNotifierProvider.value(value: getIt<TTSService>()),
    // ExploreProvider 提到 root 並 eager 建立,讓首次進入發現時 DB 訂閱已完成
    ChangeNotifierProvider(create: (_) => ExploreProvider(), lazy: false),
  ];
}
