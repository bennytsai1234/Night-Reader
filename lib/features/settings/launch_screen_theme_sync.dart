import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:night_reader/features/settings/settings_provider.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';

/// 讓下次開 App 的系統啟動畫面用目前的書架底色（Android 13 起系統會記住）：
/// 淺色用淺色風格的底色，深色用深色風格的底色或純黑；各組合的底色在
/// `android/app/src/main/res/values/launch_colors.xml`。
///
/// 掛在 App 根部：啟動時告訴原生端一次，之後風格、純黑或深淺模式改了再
/// 告訴一次。
class LaunchScreenThemeSync extends StatefulWidget {
  const LaunchScreenThemeSync({super.key, required this.child});

  final Widget child;

  /// 深色書架底色的資源名：純黑時一律是 `black`，否則是深色風格的名稱。
  static String darkKey(ThemeSettingsProvider themeSettings) =>
      themeSettings.paletteFor(Brightness.dark).background ==
          const Color(0xFF000000)
      ? 'black'
      : themeSettings.darkStyle.name;

  @override
  State<LaunchScreenThemeSync> createState() => _LaunchScreenThemeSyncState();
}

class _LaunchScreenThemeSyncState extends State<LaunchScreenThemeSync> {
  static const MethodChannel _channel = MethodChannel(
    'night_reader/launch_screen',
  );

  late final SettingsProvider _settings = context.read<SettingsProvider>();
  late final ThemeSettingsProvider _themeSettings = context
      .read<ThemeSettingsProvider>();
  String? _sent;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_sync);
    _themeSettings.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    _settings.removeListener(_sync);
    _themeSettings.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    final light = _themeSettings.lightStyle.name;
    final dark = LaunchScreenThemeSync.darkKey(_themeSettings);
    final mode = _settings.themeMode.name;
    final key = '$light/$dark/$mode';
    if (key == _sent) return;
    _sent = key;
    unawaited(_send(light, dark, mode));
  }

  static Future<void> _send(String light, String dark, String mode) async {
    try {
      await _channel.invokeMethod<void>('setTheme', {
        'light': light,
        'dark': dark,
        'mode': mode,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
