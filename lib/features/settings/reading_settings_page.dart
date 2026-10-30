import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_sections.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_device_channel.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

/// 閱讀偏好：完整的排版、版面、頁首頁尾、自動翻頁、繁簡、點擊區域與音量鍵
/// 設定。和閱讀器內「外觀與排版」面板（精簡版）用同一組區塊與同一個
/// controller 型別，兩處設定的讀寫路徑一致。從閱讀器「外觀與排版 → 更多排版
/// 設定」或下方選單的「進階」進來時，閱讀器等這一頁關掉才重讀設定。
class ReadingSettingsPage extends StatefulWidget {
  const ReadingSettingsPage({super.key});

  @override
  State<ReadingSettingsPage> createState() => _ReadingSettingsPageState();
}

class _ReadingSettingsPageState extends State<ReadingSettingsPage> {
  final ReaderV2SettingsController _settings = ReaderV2SettingsController();
  late final ReaderV2SettingsGroups _groups = ReaderV2SettingsGroups(_settings);
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
    // 還沒提交的步進先提交，再釋放控制器。
    _groups.dispose();
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: '閱讀偏好'),
      // 一組是清單的一項，進頁時只建畫面上看得到的組；每一列只聽自己的值。
      // 「頁尾位置」這一列的有無跟著頁尾設定變，變了才重排各組（ADR 0029）。
      body: ValueListenableBuilder<bool>(
        valueListenable: _groups.shape,
        builder: (context, _, _) => GroupedListView(
          children: [
            _groups.typography(),
            ..._groups.pageLayout(),
            _groups.autoPage(),
            _groups.chineseConvert(),
            _groups.clickActions(),
            if (ReaderV2DeviceChannel.supportsVolumeKeys) _groups.volumeKey(),
          ],
        ),
      ),
    );
  }
}
