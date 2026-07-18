import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/services/japanese_translation_service.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_tap_action.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_setting_components.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/shared/theme/app_theme.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';

class ReaderV2SettingsSheets {
  const ReaderV2SettingsSheets._();

  static void showInterfaceSettings(
    BuildContext context,
    ReaderV2SettingsController settings,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReaderInterfaceSheet(settings: settings),
    );
  }

  static void showAdvancedSettings(
    BuildContext context,
    ReaderV2SettingsController settings, {
    VoidCallback? onChangeSource,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => _ReaderAdvancedSheet(
            settings: settings,
            onChangeSource: onChangeSource,
          ),
    );
  }
}

class _ReaderInterfaceSheet extends StatefulWidget {
  const _ReaderInterfaceSheet({required this.settings});

  final ReaderV2SettingsController settings;

  @override
  State<_ReaderInterfaceSheet> createState() => _ReaderInterfaceSheetState();
}

class _ReaderInterfaceSheetState extends State<_ReaderInterfaceSheet> {
  final Map<String, Timer> _debouncers = <String, Timer>{};
  late double _fontSize;
  late double _lineHeight;
  late double _letterSpacing;
  late double _paragraphSpacing;

  @override
  void initState() {
    super.initState();
    final settings = widget.settings;
    _fontSize = settings.fontSize;
    _lineHeight = settings.lineHeight;
    _letterSpacing = settings.letterSpacing;
    _paragraphSpacing = settings.paragraphSpacing;
  }

  @override
  void dispose() {
    for (final timer in _debouncers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  void _scheduleCommit(String key, VoidCallback action) {
    _debouncers.remove(key)?.cancel();
    _debouncers[key] = Timer(const Duration(milliseconds: 120), action);
  }

  void _commitNow(String key, VoidCallback action) {
    _debouncers.remove(key)?.cancel();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return AppBottomSheet(
      title: '界面設定',
      icon: Icons.format_paint_outlined,
      children: [
        const SheetSection(
          title: '閱讀主題',
          trailing: Text(
            '正文背景與文字',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
        ListenableBuilder(
          listenable: settings,
          builder:
              (context, _) => _ReaderThemeSelector(
                selectedIndex: settings.themeIndex,
                onSelected: settings.setTheme,
              ),
        ),
        const SheetSection(
          title: '選單樣式',
          trailing: Text(
            '選單與工具列配色',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
        ListenableBuilder(
          listenable: settings,
          builder:
              (context, _) => _ReaderThemeSelector(
                selectedIndex: settings.menuThemeIndex,
                onSelected: settings.setMenuTheme,
              ),
        ),
        const SheetSection(title: '排版精修'),
        ReaderV2SettingComponents.buildSliderRow(
          label: '字號',
          value: _fontSize,
          min: 14,
          max: 40,
          onChanged: (value) {
            setState(() => _fontSize = value);
            _scheduleCommit('fontSize', () => settings.setFontSize(_fontSize));
          },
          onChangeEnd: (value) {
            _commitNow('fontSize', () => settings.setFontSize(value));
          },
        ),
        ReaderV2SettingComponents.buildSliderRow(
          label: '行高',
          value: _lineHeight,
          min: ReaderV2SettingsController.minReadableLineHeight,
          max: 3.0,
          onChanged: (value) {
            setState(() => _lineHeight = value);
            _scheduleCommit(
              'lineHeight',
              () => settings.setLineHeight(_lineHeight),
            );
          },
          onChangeEnd: (value) {
            _commitNow('lineHeight', () => settings.setLineHeight(value));
          },
        ),
        ReaderV2SettingComponents.buildSliderRow(
          label: '字距',
          value: _letterSpacing,
          min: 0.0,
          max: 4.0,
          onChanged: (value) {
            setState(() => _letterSpacing = value);
            _scheduleCommit(
              'letterSpacing',
              () => settings.setLetterSpacing(_letterSpacing),
            );
          },
          onChangeEnd: (value) {
            _commitNow('letterSpacing', () => settings.setLetterSpacing(value));
          },
        ),
        ReaderV2SettingComponents.buildSliderRow(
          label: '段距',
          value: _paragraphSpacing,
          min: 0.0,
          max: 3.0,
          onChanged: (value) {
            setState(() => _paragraphSpacing = value);
            _scheduleCommit(
              'paragraphSpacing',
              () => settings.setParagraphSpacing(_paragraphSpacing),
            );
          },
          onChangeEnd: (value) {
            _commitNow(
              'paragraphSpacing',
              () => settings.setParagraphSpacing(value),
            );
          },
        ),
        ListenableBuilder(
          listenable: settings,
          builder:
              (context, _) => Row(
                children: [
                  const SizedBox(
                    width: 65,
                    child: Text('首行縮排', style: TextStyle(fontSize: 12)),
                  ),
                  const Spacer(),
                  DropdownButton<int>(
                    value: settings.textIndent,
                    underline: const SizedBox.shrink(),
                    items:
                        [0, 1, 2, 4]
                            .map(
                              (i) => DropdownMenuItem(
                                value: i,
                                child: Text('$i 字'),
                              ),
                            )
                            .toList(),
                    onChanged: (value) {
                      if (value != null) settings.setTextIndent(value);
                    },
                  ),
                ],
              ),
        ),
        const SheetSection(title: '排版進階'),
        ListenableBuilder(
          listenable: settings,
          builder:
              (context, _) => _ReaderTypographySwitches(settings: settings),
        ),
      ],
    );
  }
}

class _ReaderTypographySwitches extends StatelessWidget {
  const _ReaderTypographySwitches({required this.settings});

  final ReaderV2SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSwitch(
          title: '末行字距補償（B2）',
          subtitle: '讓末行貼近上方滿行字距；每段會額外排版一次',
          value: settings.lastLineSpacingCompensation,
          onChanged: settings.setLastLineSpacingCompensation,
        ),
      ],
    );
  }

  Widget _buildSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _ReaderThemeSelector extends StatelessWidget {
  const _ReaderThemeSelector({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: AppTheme.readingThemes.length,
        itemBuilder: (context, index) {
          final theme = AppTheme.readingThemes[index];
          final selected = selectedIndex == index;
          return Semantics(
            label: theme.name,
            selected: selected,
            button: true,
            child: GestureDetector(
              onTap: () => onSelected(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 52,
                margin: const EdgeInsets.only(right: 14),
                decoration: BoxDecoration(
                  color: theme.backgroundColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.withValues(alpha: 0.2),
                    width: selected ? 3 : 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    'Aa',
                    style: TextStyle(
                      color: theme.textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReaderAdvancedSheet extends StatelessWidget {
  const _ReaderAdvancedSheet({required this.settings, this.onChangeSource});

  final ReaderV2SettingsController settings;
  final VoidCallback? onChangeSource;

  @override
  Widget build(BuildContext context) {
    final changeSource = onChangeSource;
    // 開 sheet 時刷新一次模型狀態，讓日文翻譯列的 subtitle 反映現況。
    unawaited(MlkitJapaneseTranslator.instance.areModelsDownloaded());
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return AppBottomSheet(
          title: '進階設定',
          icon: Icons.tune_rounded,
          children: [
            if (changeSource != null) ...[
              const SheetSection(title: '書源'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.swap_horiz),
                title: const Text('換源', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '搜尋其他書源並切換本書來源',
                  style: TextStyle(fontSize: 11),
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () {
                  Navigator.pop(context);
                  changeSource();
                },
              ),
              const Divider(height: 32),
            ],
            const SheetSection(title: '自動翻頁'),
            ReaderV2SettingComponents.buildSliderRow(
              label: '速度',
              value: settings.autoPageSpeed,
              min: ReaderV2SettingsController.minAutoPageSpeed,
              max: ReaderV2SettingsController.maxAutoPageSpeed,
              divisions: 43,
              onChanged: settings.setAutoPageSpeed,
              valueFormatter: (value) => '${(value * 100).round()}%',
            ),
            const Divider(height: 32),
            const SheetSection(title: '繁簡轉換'),
            Wrap(
              spacing: 12,
              children: [
                ChoiceChip(
                  label: const Text('不轉換'),
                  selected: settings.chineseConvert == 0,
                  onSelected:
                      (selected) =>
                          selected ? settings.setChineseConvert(0) : null,
                ),
                ChoiceChip(
                  label: const Text('簡轉繁'),
                  selected: settings.chineseConvert == 1,
                  onSelected:
                      (selected) =>
                          selected ? settings.setChineseConvert(1) : null,
                ),
                ChoiceChip(
                  label: const Text('繁轉簡'),
                  selected: settings.chineseConvert == 2,
                  onSelected:
                      (selected) =>
                          selected ? settings.setChineseConvert(2) : null,
                ),
              ],
            ),
            const Divider(height: 32),
            const SheetSection(title: '日文翻譯'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('日文段落自動翻譯', style: TextStyle(fontSize: 14)),
              subtitle: ValueListenableBuilder<JapaneseModelStatus>(
                valueListenable: MlkitJapaneseTranslator.instance.status,
                builder:
                    (context, status, _) => Text(
                      _japaneseModelSubtitle(status),
                      style: const TextStyle(fontSize: 11),
                    ),
              ),
              value: settings.japaneseAutoTranslate,
              onChanged: (value) {
                settings.setJapaneseAutoTranslate(value);
                if (value) {
                  unawaited(MlkitJapaneseTranslator.instance.ensureModels());
                }
              },
            ),
            const Divider(height: 32),
            const SheetSection(
              title: '點擊區域設定',
              trailing: Text(
                '九宮格配置',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 8),
            _ClickActionGrid(settings: settings),
          ],
        );
      },
    );
  }
}

class _ClickActionGrid extends StatelessWidget {
  const _ClickActionGrid({required this.settings});

  final ReaderV2SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 2.2,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: 9,
        itemBuilder: (context, index) {
          final action = settings.clickActions[index];
          final label = ReaderV2TapAction.fromCode(action).label;
          final isCenter = index == 4;
          return GestureDetector(
            onTap: () => _showActionPicker(context, index),
            child: Container(
              decoration: BoxDecoration(
                color:
                    isCenter
                        ? Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.5)
                        : Theme.of(context).colorScheme.surfaceContainer,
                border: Border.all(
                  color:
                      isCenter
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.withValues(alpha: 0.1),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: isCenter ? FontWeight.bold : FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showActionPicker(BuildContext context, int gridIndex) {
    AppBottomSheet.show(
      context: context,
      title: '選擇點擊功能',
      icon: Icons.ads_click,
      children:
          ReaderV2TapAction.values.map((action) {
            final selected = settings.clickActions[gridIndex] == action.code;
            return ListTile(
              title: Text(action.label, style: const TextStyle(fontSize: 14)),
              trailing:
                  selected
                      ? Icon(
                        Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary,
                      )
                      : null,
              onTap: () {
                settings.setClickAction(gridIndex, action.code);
                Navigator.pop(context);
              },
            );
          }).toList(),
    );
  }
}

String _japaneseModelSubtitle(JapaneseModelStatus status) {
  switch (status) {
    case JapaneseModelStatus.downloading:
      return '翻譯模型下載中（約 60MB，需 Wi-Fi）…';
    case JapaneseModelStatus.ready:
      return '含假名段落自動離線翻譯為中文';
    case JapaneseModelStatus.failed:
      return '模型下載失敗，請連上 Wi-Fi 後重新開啟';
    case JapaneseModelStatus.missing:
    case JapaneseModelStatus.unknown:
      return '首次啟用需下載離線模型（約 60MB，Wi-Fi）';
  }
}
