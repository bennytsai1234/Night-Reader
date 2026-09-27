import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_tap_action.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_prefs_repository.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/number_stepper_row.dart';

// 閱讀設定區塊：閱讀器內面板與「閱讀偏好」設定頁共用同一組元件，
// 皆透過 ReaderV2SettingsController 讀寫，確保兩處行為與資料一致。

/// 排版區塊：字號、行高為常用項；字距、段距、縮排與進階排版為次要項。
///
/// [collapsible] 為 true 時次要項收合在「更多排版」之下，
/// 讓閱讀器內的面板維持低高度、正文保持可見。
class ReaderV2TypographySection extends StatefulWidget {
  const ReaderV2TypographySection({
    super.key,
    required this.settings,
    this.collapsible = false,
    this.moreChildren = const <Widget>[],
  });

  final ReaderV2SettingsController settings;
  final bool collapsible;

  /// 附加在次要項之後的內容（例如閱讀器面板的選單樣式）。
  final List<Widget> moreChildren;

  @override
  State<ReaderV2TypographySection> createState() =>
      _ReaderV2TypographySectionState();
}

class _ReaderV2TypographySectionState extends State<ReaderV2TypographySection> {
  // 排版變更會觸發正文重新排版；連按或長按步進時合併為一次提交。
  static const _commitDelay = Duration(milliseconds: 120);

  Timer? _typographyCommitTimer;
  bool _fontSizeDirty = false;
  bool _lineHeightDirty = false;
  bool _letterSpacingDirty = false;
  bool _paragraphSpacingDirty = false;
  late double _fontSize;
  late double _lineHeight;
  late double _letterSpacing;
  late double _paragraphSpacing;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    final settings = widget.settings;
    _fontSize = settings.fontSize;
    _lineHeight = settings.lineHeight;
    _letterSpacing = settings.letterSpacing;
    _paragraphSpacing = settings.paragraphSpacing;
    settings.addListener(_syncTypographyFromSettings);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_syncTypographyFromSettings);
    _commitTypographyNow();
    super.dispose();
  }

  bool get _hasDirtyTypography =>
      _fontSizeDirty ||
      _lineHeightDirty ||
      _letterSpacingDirty ||
      _paragraphSpacingDirty;

  bool get _isDefault {
    final defaults = ReaderV2PrefsSnapshot.defaults();
    return _fontSize == defaults.fontSize &&
        _lineHeight == defaults.lineHeight &&
        _letterSpacing == defaults.letterSpacing &&
        _paragraphSpacing == defaults.paragraphSpacing &&
        widget.settings.textIndent == defaults.textIndent;
  }

  void _syncTypographyFromSettings() {
    if (!mounted) return;
    final settings = widget.settings;
    // controller 的通知也可能只是縮排或主題變更；統一重建以更新相依顯示。
    setState(() {
      if (!_fontSizeDirty) _fontSize = settings.fontSize;
      if (!_lineHeightDirty) _lineHeight = settings.lineHeight;
      if (!_letterSpacingDirty) _letterSpacing = settings.letterSpacing;
      if (!_paragraphSpacingDirty) {
        _paragraphSpacing = settings.paragraphSpacing;
      }
    });
  }

  void _scheduleTypographyCommit() {
    _typographyCommitTimer?.cancel();
    _typographyCommitTimer = Timer(_commitDelay, _commitTypography);
  }

  void _commitTypographyNow() {
    _typographyCommitTimer?.cancel();
    _typographyCommitTimer = null;
    _commitTypography();
  }

  void _commitTypography() {
    _typographyCommitTimer = null;
    if (!_hasDirtyTypography) return;
    final fontSize = _fontSizeDirty ? _fontSize : null;
    final lineHeight = _lineHeightDirty ? _lineHeight : null;
    final letterSpacing = _letterSpacingDirty ? _letterSpacing : null;
    final paragraphSpacing = _paragraphSpacingDirty ? _paragraphSpacing : null;
    _clearDirty();
    widget.settings.setTypography(
      fontSize: fontSize,
      lineHeight: lineHeight,
      letterSpacing: letterSpacing,
      paragraphSpacing: paragraphSpacing,
    );
  }

  void _clearDirty() {
    _fontSizeDirty = false;
    _lineHeightDirty = false;
    _letterSpacingDirty = false;
    _paragraphSpacingDirty = false;
  }

  void _reset() {
    // 丟棄尚未提交的步進，避免延遲提交把預設值覆蓋回去。
    _typographyCommitTimer?.cancel();
    _typographyCommitTimer = null;
    _clearDirty();
    widget.settings.resetTypography();
    _syncTypographyFromSettings();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final colorScheme = Theme.of(context).colorScheme;
    final secondary = <Widget>[
      NumberStepperRow(
        label: '字距',
        value: _letterSpacing,
        min: 0.0,
        max: 4.0,
        step: 0.1,
        fractionDigits: 1,
        onChanged: (value) {
          setState(() => _letterSpacing = value);
          _letterSpacingDirty = true;
          _scheduleTypographyCommit();
        },
      ),
      NumberStepperRow(
        label: '段距',
        value: _paragraphSpacing,
        min: 0.0,
        max: 3.0,
        step: 0.1,
        fractionDigits: 1,
        onChanged: (value) {
          setState(() => _paragraphSpacing = value);
          _paragraphSpacingDirty = true;
          _scheduleTypographyCommit();
        },
      ),
      _TextIndentSelector(
        value: settings.textIndent,
        onChanged: settings.setTextIndent,
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(
          '末行字距補償',
          style: AppTextStyles.uiMd.copyWith(color: colorScheme.onSurface),
        ),
        subtitle: Text(
          '讓末行貼近上方滿行字距；每段會額外排版一次',
          style: AppTextStyles.bodyXs.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        value: settings.lastLineSpacingCompensation,
        onChanged: settings.setLastLineSpacingCompensation,
      ),
      ...widget.moreChildren,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetSection(
          title: '排版',
          trailing: TextButton(
            onPressed: _isDefault ? null : _reset,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: AppTextStyles.uiSm,
            ),
            child: const Text('恢復預設'),
          ),
        ),
        NumberStepperRow(
          label: '字號',
          value: _fontSize,
          min: 14,
          max: 40,
          step: 1,
          onChanged: (value) {
            setState(() => _fontSize = value);
            _fontSizeDirty = true;
            _scheduleTypographyCommit();
          },
        ),
        NumberStepperRow(
          label: '行高',
          value: _lineHeight,
          min: ReaderV2SettingsController.minReadableLineHeight,
          max: ReaderV2SettingsController.maxReadableLineHeight,
          step: 0.1,
          fractionDigits: 1,
          onChanged: (value) {
            setState(() => _lineHeight = value);
            _lineHeightDirty = true;
            _scheduleTypographyCommit();
          },
        ),
        if (!widget.collapsible)
          ...secondary
        else ...[
          _ExpandToggle(
            label: '更多排版',
            expanded: _expanded,
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: secondary,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ],
    );
  }
}

class _ExpandToggle extends StatelessWidget {
  const _ExpandToggle({
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      expanded: expanded,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardMd,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.uiSm.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.expand_more_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextIndentSelector extends StatelessWidget {
  const _TextIndentSelector({required this.value, required this.onChanged});

  static const _options = [0, 1, 2, 4];

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return _LabeledRow(
      label: '首行縮排',
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          for (final option in _options)
            ButtonSegment(value: option, label: Text('$option 字')),
        ],
        // 舊版或外部寫入的非選項值仍需顯示，不選取任何分段。
        selected: _options.contains(value) ? {value} : const {},
        emptySelectionAllowed: !_options.contains(value),
        onSelectionChanged: (selection) {
          if (selection.isNotEmpty) onChanged(selection.first);
        },
      ),
    );
  }
}

class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.uiMd.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// 自動翻頁速度。
class ReaderV2AutoPageSection extends StatelessWidget {
  const ReaderV2AutoPageSection({super.key, required this.settings});

  final ReaderV2SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetSection(title: '自動翻頁'),
          NumberStepperRow(
            label: '速度',
            value: settings.autoPageSpeed,
            min: ReaderV2SettingsController.minAutoPageSpeed,
            max: ReaderV2SettingsController.maxAutoPageSpeed,
            step: 0.01,
            displayScale: 100,
            unit: '%',
            onChanged: settings.setAutoPageSpeed,
          ),
        ],
      ),
    );
  }
}

/// 繁簡轉換。
class ReaderV2ChineseConvertSection extends StatelessWidget {
  const ReaderV2ChineseConvertSection({super.key, required this.settings});

  final ReaderV2SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetSection(title: '繁簡轉換'),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('不轉換')),
              ButtonSegment(value: 1, label: Text('簡轉繁')),
              ButtonSegment(value: 2, label: Text('繁轉簡')),
            ],
            selected: {settings.chineseConvert},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) {
                settings.setChineseConvert(selection.first);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// 九宮格點擊區域設定。
class ReaderV2ClickActionSection extends StatelessWidget {
  const ReaderV2ClickActionSection({super.key, required this.settings});

  final ReaderV2SettingsController settings;

  bool get _isDefault {
    final defaults = ReaderV2TapAction.defaultGrid();
    for (var i = 0; i < defaults.length; i++) {
      if (settings.clickActions[i] != defaults[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final colorScheme = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetSection(
              title: '點擊區域',
              trailing: TextButton(
                onPressed: _isDefault ? null : settings.resetClickActions,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: AppTextStyles.uiSm,
                ),
                child: const Text('恢復預設'),
              ),
            ),
            Text(
              '對應閱讀畫面的九宮格，點一格即可更換功能。',
              style: AppTextStyles.bodySm.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 1.6,
                crossAxisSpacing: AppSpacing.sm,
                mainAxisSpacing: AppSpacing.sm,
              ),
              itemCount: 9,
              itemBuilder: (context, index) {
                final label = ReaderV2TapAction.fromCode(
                  settings.clickActions[index],
                ).label;
                final isCenter = index == 4;
                return Material(
                  color: isCenter
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.cardMd,
                    side: BorderSide(
                      color: isCenter
                          ? colorScheme.primary
                          : colorScheme.outlineVariant,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: AppRadius.cardMd,
                    onTap: () => _showActionPicker(context, index),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.uiSm.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: isCenter
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _showActionPicker(BuildContext context, int gridIndex) {
    final colorScheme = Theme.of(context).colorScheme;
    AppBottomSheet.show(
      context: context,
      title: '選擇點擊功能',
      icon: Icons.ads_click,
      children: ReaderV2TapAction.values.map((action) {
        final selected = settings.clickActions[gridIndex] == action.code;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(action.label, style: AppTextStyles.uiMd),
          trailing: selected
              ? Icon(Icons.check_circle, color: colorScheme.primary)
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
