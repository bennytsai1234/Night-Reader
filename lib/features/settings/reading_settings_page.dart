import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/core/constant/page_anim.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
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

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final snapshot = await _prefsRepository.load();
    if (!mounted) return;
    setState(() {
      _prefs = snapshot;
    });
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
      appBar: AppBar(title: const Text('閱讀設定')),
      body:
          prefs == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                children: [
                  _buildSectionTitle('操作'),
                  ListTile(
                    title: const Text('點擊區域設定 (打點區)'),
                    subtitle: const Text('自訂螢幕各點擊區塊的對應行為'),
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
                  _buildSectionTitle('排版'),
                  ReaderV2SettingComponents.buildSliderRow(
                    label: '字號',
                    value: prefs.fontSize,
                    min: 14,
                    max: 40,
                    onChanged: (value) {
                      _updatePrefs(prefs.copyWith(fontSize: value));
                      _prefsRepository.saveFontSize(value);
                    },
                  ),
                  ReaderV2SettingComponents.buildSliderRow(
                    label: '行高',
                    value: prefs.lineHeight,
                    min: ReaderV2Style.minReadableLineHeight,
                    max: ReaderV2Style.maxReadableLineHeight,
                    onChanged: (value) {
                      _updatePrefs(prefs.copyWith(lineHeight: value));
                      _prefsRepository.saveLineHeight(value);
                    },
                  ),
                  ReaderV2SettingComponents.buildSliderRow(
                    label: '字距',
                    value: prefs.letterSpacing,
                    min: 0.0,
                    max: 4.0,
                    onChanged: (value) {
                      _updatePrefs(prefs.copyWith(letterSpacing: value));
                      _prefsRepository.saveLetterSpacing(value);
                    },
                  ),
                  ReaderV2SettingComponents.buildSliderRow(
                    label: '段距',
                    value: prefs.paragraphSpacing,
                    min: 0.0,
                    max: 3.0,
                    onChanged: (value) {
                      _updatePrefs(prefs.copyWith(paragraphSpacing: value));
                      _prefsRepository.saveParagraphSpacing(value);
                    },
                  ),
                  ListTile(
                    title: const Text('首行縮排'),
                    trailing: DropdownButton<int>(
                      value: prefs.textIndent,
                      underline: const SizedBox.shrink(),
                      items:
                          const [0, 1, 2, 4]
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text('$value 字'),
                                ),
                              )
                              .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        _updatePrefs(prefs.copyWith(textIndent: value));
                        _prefsRepository.saveTextIndent(value);
                      },
                    ),
                  ),
                  ListTile(
                    title: const Text('翻頁模式'),
                    subtitle: Wrap(
                      spacing: 8,
                      children: [
                        ReaderV2SettingComponents.buildChoiceChip(
                          label: '平移翻頁',
                          value: PageAnim.slide,
                          groupValue: prefs.pageTurnMode,
                          onSelected: (value) {
                            _updatePrefs(prefs.copyWith(pageTurnMode: value));
                            _prefsRepository.savePageTurnMode(value);
                          },
                        ),
                        ReaderV2SettingComponents.buildChoiceChip(
                          label: '上下滾動',
                          value: PageAnim.scroll,
                          groupValue: prefs.pageTurnMode,
                          onSelected: (value) {
                            _updatePrefs(prefs.copyWith(pageTurnMode: value));
                            _prefsRepository.savePageTurnMode(value);
                          },
                        ),
                      ],
                    ),
                  ),
                  ReaderV2SettingComponents.buildSliderRow(
                    label: '自動速度',
                    value: prefs.autoPageSpeed,
                    min: 0.08,
                    max: 0.45,
                    divisions: 37,
                    valueFormatter: (value) => '${(value * 100).round()}%',
                    onChanged: (value) {
                      _updatePrefs(prefs.copyWith(autoPageSpeed: value));
                      _prefsRepository.saveAutoPageSpeed(value);
                    },
                  ),

                  const Divider(),
                  _buildSectionTitle('內容'),
                  ListTile(
                    title: const Text('繁簡轉換'),
                    subtitle: Wrap(
                      spacing: 8,
                      children: [
                        ReaderV2SettingComponents.buildChoiceChip(
                          label: '不轉換',
                          value: 0,
                          groupValue: prefs.chineseConvert,
                          onSelected: (value) {
                            _updatePrefs(prefs.copyWith(chineseConvert: value));
                            _prefsRepository.saveChineseConvert(value);
                          },
                        ),
                        ReaderV2SettingComponents.buildChoiceChip(
                          label: '簡轉繁',
                          value: 1,
                          groupValue: prefs.chineseConvert,
                          onSelected: (value) {
                            _updatePrefs(prefs.copyWith(chineseConvert: value));
                            _prefsRepository.saveChineseConvert(value);
                          },
                        ),
                        ReaderV2SettingComponents.buildChoiceChip(
                          label: '繁轉簡',
                          value: 2,
                          groupValue: prefs.chineseConvert,
                          onSelected: (value) {
                            _updatePrefs(prefs.copyWith(chineseConvert: value));
                            _prefsRepository.saveChineseConvert(value);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        title,
        style: AppTextStyles.bodyXs.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
