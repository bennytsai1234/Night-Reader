import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_sections.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

/// 閱讀偏好：與閱讀器內「外觀與排版」「進階設定」面板使用同一組區塊與
/// 同一個 controller 型別，兩處設定的讀寫路徑一致。
class ReadingSettingsPage extends StatefulWidget {
  const ReadingSettingsPage({super.key});

  @override
  State<ReadingSettingsPage> createState() => _ReadingSettingsPageState();
}

class _ReadingSettingsPageState extends State<ReadingSettingsPage> {
  final ReaderV2SettingsController _settings = ReaderV2SettingsController();
  late final StreamSubscription<String> _saveFailures;

  @override
  void initState() {
    super.initState();
    _saveFailures = _settings.saveFailures.listen(_showMessage);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    unawaited(_saveFailures.cancel());
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: '閱讀偏好'),
      // 每個區塊是清單裡的一列，進頁時只建畫面上看得到的幾塊；原本整頁包在
      // 一個 Column 裡，換頁的第一幀把六個區塊全部建好、排好（ADR 0018）。
      body: GroupedListView(
        children: [
          for (final section in <Widget>[
            ReaderV2TypographySection(settings: _settings),
            ReaderV2PageLayoutSection(settings: _settings),
            ReaderV2AutoPageSection(settings: _settings),
            ReaderV2ChineseConvertSection(settings: _settings),
            ReaderV2ClickActionSection(settings: _settings),
            ReaderV2VolumeKeySection(settings: _settings),
          ])
            // 共用區塊不自帶左右外距（閱讀器面板另有內距），這裡補上分組外距。
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppGrouped.margin,
              ),
              child: section,
            ),
        ],
      ),
    );
  }
}
