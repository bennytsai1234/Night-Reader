import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_tap_action.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_info_item.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_prefs_repository.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_constants.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass_segmented.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/number_stepper_row.dart';

// 閱讀設定區塊：閱讀器內面板與「閱讀偏好」設定頁共用同一組元件，
// 皆透過 ReaderV2SettingsController 讀寫，確保兩處行為與資料一致。
//
// 區塊以分組卡片呈現且不自帶左右外距：設定頁與閱讀器面板各自提供水平內距，
// 同一組卡片在兩處都對齊所在容器的內容邊界。

/// 分組卡片不自帶左右外距，由所在容器決定。
const EdgeInsets _sectionMargin = EdgeInsets.zero;

/// 數值步進列放進卡片時只補列的左右內距；高度由步進列本身決定（約 44）。
Widget _stepperRow(Widget stepper) => GroupedContent(
  padding: const EdgeInsets.symmetric(horizontal: AppGrouped.rowPadding),
  child: stepper,
);

/// 組標題右側的「恢復預設」。
class _ResetButton extends StatelessWidget {
  const _ResetButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        minimumSize: Size.zero,
        textStyle: AppTextStyles.uiSm,
      ),
      child: const Text('恢復預設'),
    );
  }
}

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
  bool _titleFontSizeDirty = false;
  bool _lineHeightDirty = false;
  bool _letterSpacingDirty = false;
  bool _paragraphSpacingDirty = false;
  bool _chapterSpacingDirty = false;
  late double _fontSize;
  late double _titleFontSize;
  late double _lineHeight;
  late double _letterSpacing;
  late double _paragraphSpacing;
  late double _chapterSpacing;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    final settings = widget.settings;
    _fontSize = settings.fontSize;
    _titleFontSize = settings.titleFontSize;
    _lineHeight = settings.lineHeight;
    _letterSpacing = settings.letterSpacing;
    _paragraphSpacing = settings.paragraphSpacing;
    _chapterSpacing = settings.chapterSpacing;
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
      _titleFontSizeDirty ||
      _lineHeightDirty ||
      _letterSpacingDirty ||
      _paragraphSpacingDirty ||
      _chapterSpacingDirty;

  bool get _isDefault {
    final defaults = ReaderV2PrefsSnapshot.defaults();
    return _fontSize == defaults.fontSize &&
        _titleFontSize == defaults.titleFontSize &&
        _lineHeight == defaults.lineHeight &&
        _letterSpacing == defaults.letterSpacing &&
        _paragraphSpacing == defaults.paragraphSpacing &&
        _chapterSpacing == defaults.chapterSpacing &&
        widget.settings.textIndent == defaults.textIndent;
  }

  void _syncTypographyFromSettings() {
    if (!mounted) return;
    final settings = widget.settings;
    // controller 的通知也可能只是縮排或主題變更；統一重建以更新相依顯示。
    setState(() {
      if (!_fontSizeDirty) _fontSize = settings.fontSize;
      if (!_titleFontSizeDirty) _titleFontSize = settings.titleFontSize;
      if (!_lineHeightDirty) _lineHeight = settings.lineHeight;
      if (!_letterSpacingDirty) _letterSpacing = settings.letterSpacing;
      if (!_paragraphSpacingDirty) {
        _paragraphSpacing = settings.paragraphSpacing;
      }
      if (!_chapterSpacingDirty) _chapterSpacing = settings.chapterSpacing;
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
    final titleFontSize = _titleFontSizeDirty ? _titleFontSize : null;
    final lineHeight = _lineHeightDirty ? _lineHeight : null;
    final letterSpacing = _letterSpacingDirty ? _letterSpacing : null;
    final paragraphSpacing = _paragraphSpacingDirty ? _paragraphSpacing : null;
    final chapterSpacing = _chapterSpacingDirty ? _chapterSpacing : null;
    _clearDirty();
    widget.settings.setTypography(
      fontSize: fontSize,
      titleFontSize: titleFontSize,
      lineHeight: lineHeight,
      letterSpacing: letterSpacing,
      paragraphSpacing: paragraphSpacing,
      chapterSpacing: chapterSpacing,
    );
  }

  void _clearDirty() {
    _fontSizeDirty = false;
    _titleFontSizeDirty = false;
    _lineHeightDirty = false;
    _letterSpacingDirty = false;
    _paragraphSpacingDirty = false;
    _chapterSpacingDirty = false;
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
    final primary = <Widget>[
      _stepperRow(
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
      ),
      _stepperRow(
        NumberStepperRow(
          label: '標題字號',
          value: _titleFontSize,
          min: 14,
          max: 48,
          step: 1,
          onChanged: (value) {
            setState(() => _titleFontSize = value);
            _titleFontSizeDirty = true;
            _scheduleTypographyCommit();
          },
        ),
      ),
      _stepperRow(
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
      ),
    ];
    final secondary = <Widget>[
      _stepperRow(
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
      ),
      _stepperRow(
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
      ),
      _stepperRow(
        NumberStepperRow(
          label: '章節間距',
          value: _chapterSpacing,
          min: ReaderV2SettingsController.minChapterSpacing,
          max: ReaderV2SettingsController.maxChapterSpacing,
          step: 0.5,
          fractionDigits: 1,
          unit: '行',
          onChanged: (value) {
            setState(() => _chapterSpacing = value);
            _chapterSpacingDirty = true;
            _scheduleTypographyCommit();
          },
        ),
      ),
      _TextIndentSelector(
        value: settings.textIndent,
        onChanged: settings.setTextIndent,
      ),
    ];
    final showSecondary = !widget.collapsible || _expanded;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupedSection(
          margin: _sectionMargin,
          header: '排版',
          headerTrailing: _ResetButton(onPressed: _isDefault ? null : _reset),
          children: [
            ...primary,
            if (showSecondary) ...secondary,
            if (widget.collapsible)
              _ExpandToggle(
                label: '更多排版',
                expanded: _expanded,
                onTap: () => setState(() => _expanded = !_expanded),
              ),
          ],
        ),
        if (showSecondary) ...widget.moreChildren,
      ],
    );
    if (!widget.collapsible) return content;
    return AnimatedSize(
      duration: AppMotion.menu,
      curve: AppMotion.menuCurve,
      alignment: Alignment.topCenter,
      child: content,
    );
  }
}

/// 卡片底部的展開／收合列。
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
    return Semantics(
      button: true,
      expanded: expanded,
      child: GroupedRow(
        title: label,
        accent: true,
        showChevron: false,
        onTap: onTap,
        trailing: AnimatedRotation(
          turns: expanded ? 0.5 : 0,
          duration: AppMotion.menu,
          curve: AppMotion.menuCurve,
          child: Icon(
            Icons.expand_more_rounded,
            size: 22,
            color: Theme.of(context).colorScheme.primary,
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
      // 舊版或外部寫入的非選項值仍需顯示，GlassSegmented 此時不選取任何分段。
      child: GlassSegmented<int>(
        expand: false,
        segments: [
          for (final option in _options) GlassSegment(option, '$option 字'),
        ],
        selected: value,
        onChanged: onChanged,
      ),
    );
  }
}

/// 卡片內「左側標籤、右側控件」的一列。
class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GroupedContent(
      padding: const EdgeInsets.symmetric(
        horizontal: AppGrouped.rowPadding,
        vertical: AppSpacing.xs,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppGrouped.rowMinHeight - AppSpacing.xs * 2,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyBase.copyWith(
                  height: 1.3,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

/// 版面：正文邊距、系統狀態列與頁首／頁尾資訊列。
class ReaderV2PageLayoutSection extends StatefulWidget {
  const ReaderV2PageLayoutSection({super.key, required this.settings});

  final ReaderV2SettingsController settings;

  @override
  State<ReaderV2PageLayoutSection> createState() =>
      _ReaderV2PageLayoutSectionState();
}

class _ReaderV2PageLayoutSectionState extends State<ReaderV2PageLayoutSection> {
  // 邊距變更會觸發正文重新排版；連按或長按步進時合併為一次提交。
  static const _commitDelay = Duration(milliseconds: 120);
  static const _paddingStep = 2.0;

  Timer? _commitTimer;
  double? _pendingHorizontal;
  double? _pendingTop;
  double? _pendingBottom;

  bool get _hasPending =>
      _pendingHorizontal != null || _pendingTop != null || _pendingBottom != null;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    _commitTimer?.cancel();
    _commit();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _schedule({double? horizontal, double? top, double? bottom}) {
    setState(() {
      _pendingHorizontal = horizontal ?? _pendingHorizontal;
      _pendingTop = top ?? _pendingTop;
      _pendingBottom = bottom ?? _pendingBottom;
    });
    _commitTimer?.cancel();
    _commitTimer = Timer(_commitDelay, _commit);
  }

  void _commit() {
    _commitTimer = null;
    if (!_hasPending) return;
    final horizontal = _pendingHorizontal;
    final top = _pendingTop;
    final bottom = _pendingBottom;
    _pendingHorizontal = null;
    _pendingTop = null;
    _pendingBottom = null;
    widget.settings.setPagePadding(
      horizontal: horizontal,
      top: top,
      bottom: bottom,
    );
  }

  void _reset() {
    // 丟棄尚未提交的步進，避免延遲提交把預設值覆蓋回去。
    _commitTimer?.cancel();
    _commitTimer = null;
    _pendingHorizontal = null;
    _pendingTop = null;
    _pendingBottom = null;
    widget.settings.resetPageLayout();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupedSection(
          margin: _sectionMargin,
          header: '版面',
          headerTrailing: _ResetButton(
            onPressed:
                settings.isPageLayoutDefault && !_hasPending ? null : _reset,
          ),
          children: [
            _stepperRow(
              NumberStepperRow(
                label: '左右邊距',
                value: _pendingHorizontal ?? settings.paddingHorizontal,
                min: ReaderV2SettingsController.minPagePadding,
                max: ReaderV2SettingsController.maxPagePadding,
                step: _paddingStep,
                unit: ' px',
                onChanged: (value) => _schedule(horizontal: value),
              ),
            ),
            _stepperRow(
              NumberStepperRow(
                label: '上邊距',
                value: _pendingTop ?? settings.paddingTop,
                min: ReaderV2SettingsController.minPagePadding,
                max: ReaderV2SettingsController.maxPagePadding,
                step: _paddingStep,
                unit: ' px',
                onChanged: (value) => _schedule(top: value),
              ),
            ),
            _stepperRow(
              NumberStepperRow(
                label: '下邊距',
                value: _pendingBottom ?? settings.paddingBottom,
                min: ReaderV2SettingsController.minPagePadding,
                max: ReaderV2SettingsController.maxPagePadding,
                step: _paddingStep,
                unit: ' px',
                onChanged: (value) => _schedule(bottom: value),
              ),
            ),
            if (!settings.footerInfo.isEmpty)
              _stepperRow(
                NumberStepperRow(
                  label: '頁尾位置',
                  // 未調整時顯示目前跟隨系統的實際距離，從那裡開始增減。
                  value:
                      settings.footerOffset ??
                      MediaQuery.paddingOf(context).bottom +
                          kReaderFooterAutoSpacing,
                  min: ReaderV2SettingsController.minPagePadding,
                  max: ReaderV2SettingsController.maxPagePadding,
                  step: _paddingStep,
                  unit: ' px',
                  onChanged: settings.setFooterOffset,
                ),
              ),
          ],
        ),
        GroupedSection(
          margin: _sectionMargin,
          children: [
            GroupedSwitchRow(
              title: '隱藏系統狀態列',
              value: settings.hideStatusBar,
              onChanged: settings.setHideStatusBar,
            ),
          ],
        ),
        GroupedSection(
          margin: _sectionMargin,
          header: '頁首與頁尾',
          children: [
            ..._infoSlotRows(
              title: '頁首',
              slots: settings.headerInfo,
              onChanged: settings.setHeaderInfo,
            ),
            ..._infoSlotRows(
              title: '頁尾',
              slots: settings.footerInfo,
              onChanged: settings.setFooterInfo,
            ),
          ],
        ),
      ],
    );
  }
}

/// 一條資訊列左右兩欄的內容選擇。
List<Widget> _infoSlotRows({
  required String title,
  required ReaderV2InfoSlots slots,
  required ValueChanged<ReaderV2InfoSlots> onChanged,
}) {
  return [
    _InfoItemPickerRow(
      label: '$title左側',
      value: slots.left,
      onChanged: (item) => onChanged(slots.copyWith(left: item)),
    ),
    _InfoItemPickerRow(
      label: '$title右側',
      value: slots.right,
      onChanged: (item) => onChanged(slots.copyWith(right: item)),
    ),
  ];
}

class _InfoItemPickerRow extends StatelessWidget {
  const _InfoItemPickerRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final ReaderV2InfoItem value;
  final ValueChanged<ReaderV2InfoItem> onChanged;

  @override
  Widget build(BuildContext context) {
    return GroupedRow(
      title: label,
      value: value.label,
      onTap: () => _showPicker(context),
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    final picked = await showAppActionSheet<ReaderV2InfoItem>(
      context: context,
      title: label,
      actions: [
        for (final item in ReaderV2InfoItem.values)
          AppSheetAction(
            label: item.label,
            value: item,
            selected: item == value,
          ),
      ],
    );
    if (picked != null) onChanged(picked);
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
      builder: (context, _) => GroupedSection(
        margin: _sectionMargin,
        header: '自動翻頁',
        children: [
          _stepperRow(
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
      builder: (context, _) => GroupedSection(
        margin: _sectionMargin,
        header: '繁簡轉換',
        children: [
          GroupedContent(
            child: GlassSegmented<int>(
              segments: const [
                GlassSegment(0, '不轉換'),
                GlassSegment(1, '簡轉繁'),
                GlassSegment(2, '繁轉簡'),
              ],
              selected: settings.chineseConvert,
              onChanged: settings.setChineseConvert,
            ),
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
        return GroupedSection(
          margin: _sectionMargin,
          header: '點擊區域',
          headerTrailing: _ResetButton(
            onPressed: _isDefault ? null : settings.resetClickActions,
          ),
          children: [
            GroupedContent(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: GridView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
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
                    // 格子用淡墨底與卡片區隔；中央格（預設喚起選單）以主色標示。
                    color: isCenter
                        ? colorScheme.primary.withValues(alpha: 0.12)
                        : colorScheme.onSurface.withValues(alpha: 0.05),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.cardMd,
                      side: isCenter
                          ? BorderSide(
                              color: colorScheme.primary.withValues(
                                alpha: 0.6,
                              ),
                              width: AppGlass.hairline * 2,
                            )
                          : BorderSide.none,
                    ),
                    child: InkWell(
                      customBorder: const RoundedRectangleBorder(
                        borderRadius: AppRadius.cardMd,
                      ),
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
                              color: isCenter
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
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
            ),
          ],
        );
      },
    );
  }

  Future<void> _showActionPicker(BuildContext context, int gridIndex) async {
    final current = settings.clickActions[gridIndex];
    final picked = await showAppActionSheet<ReaderV2TapAction>(
      context: context,
      title: '選擇點擊功能',
      actions: [
        for (final action in ReaderV2TapAction.values)
          AppSheetAction(
            label: action.label,
            value: action,
            selected: current == action.code,
          ),
      ],
    );
    if (picked != null) settings.setClickAction(gridIndex, picked.code);
  }
}
