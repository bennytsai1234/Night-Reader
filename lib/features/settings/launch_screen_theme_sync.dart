import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:night_reader/features/settings/settings_provider.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';

/// 讓下次開 App 的系統啟動畫面用目前風格與深淺的書架底色（Android 13 起
/// 系統會記住；各風格的底色在 `android/app/src/main/res/values/launch_colors.xml`）。
///
/// 掛在 App 根部：啟動時告訴原生端一次，之後風格或深淺模式改了再告訴一次。
class LaunchScreenThemeSync extends StatefulWidget {
  const LaunchScreenThemeSync({super.key, required this.child});

  final Widget child;

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
    final style = _themeSettings.style.name;
    final mode = _settings.themeMode.name;
    final key = '$style/$mode';
    if (key == _sent) return;
    _sent = key;
    unawaited(_send(style, mode));
  }

  static Future<void> _send(String style, String mode) async {
    try {
      await _channel.invokeMethod<void>('setTheme', {
        'style': style,
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
