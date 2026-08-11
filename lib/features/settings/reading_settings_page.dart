import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_prefs_repository.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_setting_components.dart';

import 'click_action_config_page.dart';

class ReadingSettingsPage extends StatefulWidget {
  const ReadingSettingsPage({super.key});

  @override
  State<ReadingSettingsPage> createState() => _ReadingSettingsPageState();
}

class _ReadingSettingsPageState extends State<ReadingSettingsPage> {
  final ReaderV2PrefsRepository _prefsRepository =
      const ReaderV2PrefsRepository();
  ReaderV2PrefsSnapshot? _prefs;
  Object? _loadError;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final snapshot = await _prefsRepository.load();
      if (!mounted) return;
      setState(() {
        _prefs = snapshot;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = error;
      });
    }
  }

  void _updatePrefs(ReaderV2PrefsSnapshot next) {
    setState(() {
      _prefs = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _prefs;
    return Scaffold(
      appBar: AppBar(title: const Text('閱讀偏好')),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null || prefs == null
              ? _buildLoadError(context)
              : ListTileTheme(
                data: const ListTileThemeData(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                ),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  children: [
                    _buildSectionTitle('操作'),
                    ListTile(
                      title: const Text('點擊區域設定'),
                      subtitle: Text(
                        '自訂閱讀畫面各區域的點擊行為',
                        style: AppTextStyles.bodySm.copyWith(height: 1.4),
                      ),
                      leading: const Icon(Icons.touch_app),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ClickActionConfigPage(),
                          ),
                        );
                        _loadPrefs();
                      },
                    ),
                    const Divider(),
                    _buildSectionTitle('自動翻頁'),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: ReaderV2SettingComponents.buildSliderRow(
                        label: '速度',
                        value: prefs.autoPageSpeed,
                        min: ReaderV2PrefsRepository.minAutoPageSpeed,
                        max: ReaderV2PrefsRepository.maxAutoPageSpeed,
                        divisions: 43,
                        valueFormatter: (value) => '${(value * 100).round()}%',
                        onChanged: (value) {
                          _updatePrefs(
                            prefs.copyWith(autoPageSpeed: value),
                          );
                          _prefsRepository.saveAutoPageSpeed(value);
                        },
                      ),
                    ),
                    const Divider(),
                    _buildSectionTitle('內容'),
                    ListTile(
                      title: const Text('繁簡轉換'),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            ReaderV2SettingComponents.buildChoiceChip(
                              label: '不轉換',
                              value: 0,
                              groupValue: prefs.chineseConvert,
                              onSelected: (value) {
                                _updatePrefs(
                                  prefs.copyWith(chineseConvert: value),
                                );
                                _prefsRepository.saveChineseConvert(value);
                              },
                            ),
                            ReaderV2SettingComponents.buildChoiceChip(
                              label: '簡轉繁',
                              value: 1,
                              groupValue: prefs.chineseConvert,
                              onSelected: (value) {
                                _updatePrefs(
                                  prefs.copyWith(chineseConvert: value),
                                );
                                _prefsRepository.saveChineseConvert(value);
                              },
                            ),
                            ReaderV2SettingComponents.buildChoiceChip(
                              label: '繁轉簡',
                              value: 2,
                              groupValue: prefs.chineseConvert,
                              onSelected: (value) {
                                _updatePrefs(
                                  prefs.copyWith(chineseConvert: value),
                                );
                                _prefsRepository.saveChineseConvert(value);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }

  Widget _buildLoadError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('閱讀偏好載入失敗'),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: _loadPrefs,
              icon: const Icon(Icons.refresh),
              label: const Text('重試'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Text(
        title,
        style: AppTextStyles.bodySm.copyWith(
          height: 1.3,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
