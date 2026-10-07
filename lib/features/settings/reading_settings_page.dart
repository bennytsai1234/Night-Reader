import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_sections.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
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
  Object? _loadError;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _saveFailures = _settings.saveFailures.listen(_showMessage);
    _load();
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

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      await _settings.loadSettings();
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: '閱讀偏好'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? AppStateView(
              icon: Icons.error_outline,
              title: '閱讀偏好載入失敗',
              tone: AppStateTone.error,
              primaryAction: AppStateAction(
                label: '重試',
                icon: Icons.refresh,
                onPressed: _load,
              ),
            )
          : GroupedListView(
              children: [
                // 共用區塊不自帶左右外距（閱讀器面板另有內距），這裡補上分組外距。
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppGrouped.margin,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ReaderV2TypographySection(settings: _settings),
                      ReaderV2PageLayoutSection(settings: _settings),
                      ReaderV2AutoPageSection(settings: _settings),
                      ReaderV2ChineseConvertSection(settings: _settings),
                      ReaderV2ClickActionSection(settings: _settings),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
