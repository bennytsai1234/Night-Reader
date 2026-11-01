import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/features/brightness/reader_v2_brightness.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_tap_action.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_info_item.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_orientation.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_page_turn_speed.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_prefs_repository.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass_segmented.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/number_stepper_row.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

// 閱讀設定的各組：閱讀器內的外觀與排版面板與「閱讀偏好」頁共用，都透過
// ReaderV2SettingsController 讀寫，兩處行為與資料一致。
//
// 每一組是一個 GroupedSection，列是各自獨立的小元件：
// - 每一列只聽自己顯示的那個值，改一個設定只重建那一列，不重建整組或整頁。
// - 閱讀偏好頁把各組放進 GroupedListView，一組是清單的一項，進頁時只建
//   畫面上看得到的組（ADR 0029）。原本版面、狀態列與頁首頁尾是同一個元件，
//   上半在畫面上，畫面外的下半也一起建。
// - 連按步進合併成一次提交的暫存值不放在列裡（列捲出畫面就拆掉），放在
//   [ReaderV2SettingsGroups]，由所在頁面的 State 建立與釋放。

/// 閱讀設定的各組與它們的暫存值。所在頁面的 State 在 initState 建立、
/// dispose 時呼叫 [dispose]（還沒提交的步進在這時提交）。
class ReaderV2SettingsGroups {
  ReaderV2SettingsGroups(this.settings, {this.margin}) {
    settings.addListener(_onSettingsChanged);
  }

  final ReaderV2SettingsController settings;

  /// 各組卡片的外距；null 時是分組清單的預設（左右 [AppGrouped.margin]）。
  /// 閱讀器面板自己有左右內距，傳 [EdgeInsets.zero]。
  final EdgeInsetsGeometry? margin;

  // 排版與邊距變更會觸發正文重新排版；連按或長按步進時合併為一次提交。
  late final _StagedEdits<_TypographyField> _typography =
      _StagedEdits<_TypographyField>(
        settings,
        fields: _TypographyField.values,
        read: (field) => field.read(settings),
        commit: (values) => settings.setTypography(
          fontSize: values[_TypographyField.fontSize],
          titleFontSize: values[_TypographyField.titleFontSize],
          titleSpacing: values[_TypographyField.titleSpacing],
          lineHeight: values[_TypographyField.lineHeight],
          letterSpacing: values[_TypographyField.letterSpacing],
          paragraphSpacing: values[_TypographyField.paragraphSpacing],
          chapterSpacing: values[_TypographyField.chapterSpacing],
          textIndent: values[_TypographyField.textIndent]?.round(),
        ),
      );

  late final _StagedEdits<_PaddingField> _padding = _StagedEdits<_PaddingField>(
    settings,
    fields: _PaddingField.values,
    read: (field) => field.read(settings),
    commit: (values) {
      settings.setPagePadding(
        top: values[_PaddingField.top],
        bottom: values[_PaddingField.bottom],
      );
      final lineChars = values[_PaddingField.lineChars];
      if (lineChars != null) settings.setLineChars(lineChars.round());
    },
  );

  /// 跟著別的設定出現的列在不在：「頁尾位置」（頁尾兩欄都不顯示時拿掉）、
  /// 「一起隱藏導覽列」（隱藏狀態列時才有）與「反向」（音量鍵翻頁打開時
  /// 才有）。列的有無跟著設定變時通知，所在頁面照它重建各組；列裡的值
  /// 變了不通知。
  ValueListenable<Object> get shape => _shape;
  late final ValueNotifier<_Shape> _shape = ValueNotifier<_Shape>(_shapeNow);

  _Shape get _shapeNow => (
    footer: !settings.footerInfo.isEmpty,
    statusBarHidden: settings.hideStatusBar,
    volumeKey: settings.volumeKeyPage,
  );

  void _onSettingsChanged() {
    _shape.value = _shapeNow;
  }

  void dispose() {
    settings.removeListener(_onSettingsChanged);
    _typography.dispose();
    _padding.dispose();
    _shape.dispose();
  }

  // ---------- 排版 ----------

  bool get _typographyIsDefault {
    final defaults = ReaderV2PrefsSnapshot.defaults();
    for (final field in _TypographyField.values) {
      if (_typography.valueOf(field) != field.defaultIn(defaults)) return false;
    }
    return true;
  }

  void _resetTypography() {
    // 丟棄尚未提交的步進，避免延遲提交把預設值覆蓋回去。
    _typography.discard();
    settings.resetTypography();
  }

  /// 排版：字號、標題、行高、字距、段距與縮排。[compact] 是閱讀器面板的精簡版：
  /// 只放邊讀邊會調的字號、行高與段距；其他排版項目與「恢復預設」在閱讀
  /// 偏好頁（恢復預設會連看不到的項目一起重設）。
  GroupedSection typography({bool compact = false}) {
    final full = !compact;
    return GroupedSection(
      margin: margin,
      header: '排版',
      headerTrailing: full
          ? _Watch<bool>(
              listenable: Listenable.merge([_typography, settings]),
              select: () => _typographyIsDefault,
              builder: (context, isDefault) =>
                  _ResetButton(onPressed: isDefault ? null : _resetTypography),
            )
          : null,
      children: [
        _StagedStepper(
          edits: _typography,
          field: _TypographyField.fontSize,
          label: '字號',
          min: 14,
          max: 40,
          step: 0.5,
          fractionDigits: 1,
          trimZeroFraction: true,
        ),
        if (full)
          _StagedStepper(
            edits: _typography,
            field: _TypographyField.titleFontSize,
            label: '標題字號',
            min: 14,
            max: 48,
            step: 1,
          ),
        if (full)
          _StagedStepper(
            edits: _typography,
            field: _TypographyField.titleSpacing,
            label: '標題間距',
            min: ReaderV2SettingsController.minTitleSpacing,
            max: ReaderV2SettingsController.maxTitleSpacing,
            step: 0.1,
            fractionDigits: 1,
            unit: '行',
          ),
        _StagedStepper(
          edits: _typography,
          field: _TypographyField.lineHeight,
          label: '行高',
          min: ReaderV2SettingsController.minReadableLineHeight,
          max: ReaderV2SettingsController.maxReadableLineHeight,
          step: 0.1,
          fractionDigits: 1,
        ),
        if (full)
          _StagedStepper(
            edits: _typography,
            field: _TypographyField.letterSpacing,
            label: '字距',
            min: 0.0,
            max: 4.0,
            step: 0.1,
            fractionDigits: 1,
          ),
        _StagedStepper(
          edits: _typography,
          field: _TypographyField.paragraphSpacing,
          label: '段距',
          min: 0.0,
          max: 3.0,
          step: 0.1,
          fractionDigits: 1,
        ),
        if (full)
          _StagedStepper(
            edits: _typography,
            field: _TypographyField.chapterSpacing,
            label: '章節間距',
            min: ReaderV2SettingsController.minChapterSpacing,
            max: ReaderV2SettingsController.maxChapterSpacing,
            step: 0.5,
            fractionDigits: 1,
            unit: '行',
          ),
        if (full)
          _StagedStepper(
            edits: _typography,
            field: _TypographyField.textIndent,
            label: '首行縮排',
            min: 0,
            max: 4,
            step: 1,
            unit: '字',
          ),
      ],
    );
  }

  // ---------- 版面 ----------

  static const _paddingStep = 2.0;

  void _resetPageLayout() {
    // 丟棄尚未提交的步進，避免延遲提交把預設值覆蓋回去。
    _padding.discard();
    settings.resetPageLayout();
  }

  Widget _paddingStepper(_PaddingField field, String label) => _StagedStepper(
    edits: _padding,
    field: field,
    label: label,
    min: ReaderV2SettingsController.minPagePadding,
    max: ReaderV2SettingsController.maxPagePadding,
    step: _paddingStep,
  );

  /// 每行字數：最多調到這個畫面放得下的字數，數字是畫面上實際的字數（設的
  /// 比放得下的多時顯示放得下的數）。字號與字距改了，放得下的數跟著變。
  Widget _lineCharsStepper() => _StagedStepper(
    edits: _padding,
    field: _PaddingField.lineChars,
    label: '每行字數',
    min: ReaderV2PrefsRepository.lineCharsRange.min.toDouble(),
    max: ReaderV2PrefsRepository.lineCharsRange.max.toDouble(),
    maxOf: (context) => _lineCapacity(context).toDouble(),
    listenable: settings,
    step: 1,
    unit: '字',
  );

  int _lineCapacity(BuildContext context) =>
      settings.lineCapacityFor(MediaQuery.sizeOf(context).width);

  /// 版面：每行字數、正文邊距、系統狀態列與頁首／頁尾資訊列。[compact] 是
  /// 閱讀器面板的精簡版：只放每行字數；其他版面項目、狀態列與頁首頁尾在
  /// 閱讀偏好頁。
  List<GroupedSection> pageLayout({bool compact = false}) {
    final horizontal = _lineCharsStepper();
    if (compact) {
      return [
        GroupedSection(margin: margin, header: '版面', children: [horizontal]),
      ];
    }
    return [
      GroupedSection(
        margin: margin,
        header: '版面',
        headerTrailing: _Watch<bool>(
          listenable: Listenable.merge([_padding, settings]),
          select: () => settings.isPageLayoutDefault && !_padding.hasPending,
          builder: (context, isDefault) =>
              _ResetButton(onPressed: isDefault ? null : _resetPageLayout),
        ),
        children: [
          horizontal,
          _Watch<bool>(
            listenable: settings,
            select: () => settings.justifyText,
            builder: (context, justify) => GroupedSwitchRow(
              title: '左右對齊',
              value: justify,
              onChanged: settings.setJustifyText,
            ),
          ),
          _paddingStepper(_PaddingField.top, '上邊距'),
          _paddingStepper(_PaddingField.bottom, '下邊距'),
          // 漸隱畫在上下邊距的空隙裡，空隙比它窄時照空隙的高度。
          _StepperRow(
            _Watch<double>(
              listenable: settings,
              select: () => settings.edgeFade,
              builder: (context, fade) => NumberStepperRow(
                label: '上下緣漸隱',
                value: fade,
                min: ReaderV2PrefsRepository.minEdgeFade,
                max: ReaderV2PrefsRepository.maxEdgeFade,
                step: _paddingStep,
                onChanged: settings.setEdgeFade,
              ),
            ),
          ),
          if (_shape.value.footer)
            _StepperRow(
              _Watch<double>(
                listenable: settings,
                select: () => settings.footerOffset,
                builder: (context, offset) => NumberStepperRow(
                  label: '頁尾位置',
                  value: offset,
                  min: ReaderV2SettingsController.minPagePadding,
                  max: ReaderV2SettingsController.maxPagePadding,
                  step: _paddingStep,
                  onChanged: settings.setFooterOffset,
                ),
              ),
            ),
        ],
      ),
      GroupedSection(
        margin: margin,
        children: [
          _Watch<bool>(
            listenable: settings,
            select: () => settings.hideStatusBar,
            builder: (context, hidden) => GroupedSwitchRow(
              title: '隱藏系統狀態列',
              value: hidden,
              onChanged: settings.setHideStatusBar,
            ),
          ),
          // 只藏導覽列時，Android 碰一下畫面就把它叫回來；和狀態列一起藏才
          // 是滑動叫出、幾秒後自己收回的全螢幕。
          if (_shape.value.statusBarHidden)
            _Watch<bool>(
              listenable: settings,
              select: () => settings.hideNavigationBar,
              builder: (context, hidden) => GroupedSwitchRow(
                title: '一起隱藏導覽列',
                value: hidden,
                onChanged: settings.setHideNavigationBar,
              ),
            ),
        ],
      ),
      GroupedSection(
        margin: margin,
        header: '頁首與頁尾',
        children: [
          for (final (label, footer, right) in const [
            ('頁首左側', false, false),
            ('頁首右側', false, true),
            ('頁尾左側', true, false),
            ('頁尾右側', true, true),
          ])
            _Watch<ReaderV2InfoItem>(
              listenable: settings,
              select: () {
                final slots = footer
                    ? settings.footerInfo
                    : settings.headerInfo;
                return right ? slots.right : slots.left;
              },
              builder: (context, item) => _InfoItemPickerRow(
                label: label,
                value: item,
                onChanged: (picked) {
                  final slots = footer
                      ? settings.footerInfo
                      : settings.headerInfo;
                  final next = right
                      ? slots.copyWith(right: picked)
                      : slots.copyWith(left: picked);
                  footer
                      ? settings.setFooterInfo(next)
                      : settings.setHeaderInfo(next);
                },
              ),
            ),
          _Watch<bool>(
            listenable: settings,
            select: () => settings.use24HourClock,
            builder: (context, use24) => _LabeledRow(
              label: '時間',
              child: GlassSegmented<bool>(
                expand: false,
                segments: const [
                  GlassSegment(true, '24 小時制'),
                  GlassSegment(false, '12 小時制'),
                ],
                selected: use24,
                onChanged: settings.setUse24HourClock,
              ),
            ),
          ),
          _Watch<int>(
            listenable: settings,
            select: () => settings.progressFractionDigits,
            builder: (context, digits) => _LabeledRow(
              label: '全書進度',
              child: GlassSegmented<int>(
                expand: false,
                segments: const [
                  GlassSegment(0, '整數'),
                  GlassSegment(1, '一位小數'),
                ],
                selected: digits,
                onChanged: settings.setProgressFractionDigits,
              ),
            ),
          ),
        ],
      ),
    ];
  }

  // ---------- 翻頁 ----------

  /// 點擊、音量鍵與選單翻頁：上一屏留幾行在畫面上、捲過一屏的快慢。
  GroupedSection pageTurn() => GroupedSection(
    margin: margin,
    header: '翻頁',
    children: [
      _StepperRow(
        _Watch<int>(
          listenable: settings,
          select: () => settings.pageTurnOverlap,
          builder: (context, overlap) => NumberStepperRow(
            label: '保留行數',
            value: overlap.toDouble(),
            min: ReaderV2PrefsRepository.minPageTurnOverlap.toDouble(),
            max: ReaderV2PrefsRepository.maxPageTurnOverlap.toDouble(),
            step: 1,
            unit: '行',
            onChanged: (value) => settings.setPageTurnOverlap(value.round()),
          ),
        ),
      ),
      _Watch<ReaderV2PageTurnSpeed>(
        listenable: settings,
        select: () => settings.pageTurnSpeed,
        builder: (context, speed) => _LabeledRow(
          label: '捲動速度',
          child: GlassSegmented<ReaderV2PageTurnSpeed>(
            expand: false,
            segments: [
              for (final option in ReaderV2PageTurnSpeed.values)
                GlassSegment(option, option.label),
            ],
            selected: speed,
            onChanged: settings.setPageTurnSpeed,
          ),
        ),
      ),
    ],
  );

  // ---------- 螢幕 ----------

  /// 螢幕常亮、螢幕方向與最暗程度。[maxDim] 為 false 時不放最暗程度
  /// （平台不能調閱讀器自己的亮度，亮度條不出現，也就沒有加暗段）。
  GroupedSection screen({required bool maxDim}) => GroupedSection(
    margin: margin,
    header: '螢幕',
    children: [
      _Watch<bool>(
        listenable: settings,
        select: () => settings.keepScreenOn,
        builder: (context, on) => GroupedSwitchRow(
          title: '螢幕常亮',
          value: on,
          onChanged: settings.setKeepScreenOn,
        ),
      ),
      _Watch<ReaderV2Orientation>(
        listenable: settings,
        select: () => settings.orientation,
        builder: (context, orientation) => _LabeledRow(
          label: '螢幕方向',
          child: GlassSegmented<ReaderV2Orientation>(
            expand: false,
            segments: [
              for (final option in ReaderV2Orientation.values)
                GlassSegment(option, option.label),
            ],
            selected: orientation,
            onChanged: settings.setOrientation,
          ),
        ),
      ),
      if (maxDim)
        _StepperRow(
          _Watch<double>(
            listenable: settings,
            select: () => settings.maxDim,
            builder: (context, dim) => NumberStepperRow(
              label: '最暗程度',
              value: dim,
              min: ReaderV2Brightness.minMaxDim,
              max: ReaderV2Brightness.maxMaxDim,
              step: 0.05,
              displayScale: 100,
              unit: '%',
              onChanged: settings.setMaxDim,
            ),
          ),
        ),
    ],
  );

  // ---------- 其他 ----------

  /// 自動翻頁速度。
  GroupedSection autoPage() => GroupedSection(
    margin: margin,
    header: '自動翻頁',
    children: [
      _StepperRow(
        _Watch<double>(
          listenable: settings,
          select: () => settings.autoPageSpeed,
          builder: (context, speed) => NumberStepperRow(
            label: '速度',
            value: speed,
            min: ReaderV2SettingsController.minAutoPageSpeed,
            max: ReaderV2SettingsController.maxAutoPageSpeed,
            step: 0.01,
            displayScale: 100,
            unit: '%',
            onChanged: settings.setAutoPageSpeed,
          ),
        ),
      ),
    ],
  );

  /// 繁簡轉換。
  GroupedSection chineseConvert() => GroupedSection(
    margin: margin,
    header: '繁簡轉換',
    children: [
      GroupedContent(
        child: _Watch<int>(
          listenable: settings,
          select: () => settings.chineseConvert,
          builder: (context, mode) => GlassSegmented<int>(
            segments: const [
              GlassSegment(0, '不轉換'),
              GlassSegment(1, '簡轉繁'),
              GlassSegment(2, '繁轉簡'),
            ],
            selected: mode,
            onChanged: settings.setChineseConvert,
          ),
        ),
      ),
    ],
  );

  bool get _clickActionsAreDefault {
    final defaults = ReaderV2TapAction.defaultGrid();
    for (var i = 0; i < defaults.length; i++) {
      if (settings.clickActions[i] != defaults[i]) return false;
    }
    return true;
  }

  /// 九宮格點擊區域。
  GroupedSection clickActions() => GroupedSection(
    margin: margin,
    header: '點擊區域',
    headerTrailing: _Watch<bool>(
      listenable: settings,
      select: () => _clickActionsAreDefault,
      builder: (context, isDefault) => _ResetButton(
        onPressed: isDefault ? null : settings.resetClickActions,
      ),
    ),
    children: [
      GroupedContent(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: _Watch<List<int>>(
          listenable: settings,
          select: () => settings.clickActions,
          builder: (context, actions) => _ClickActionGrid(
            actions: actions,
            onChanged: settings.setClickAction,
          ),
        ),
      ),
    ],
  );

  /// 音量鍵翻頁：音量下是下一頁、音量上是上一頁；打開「反向」時對調。
  GroupedSection volumeKey() => GroupedSection(
    margin: margin,
    children: [
      _Watch<bool>(
        listenable: settings,
        select: () => settings.volumeKeyPage,
        builder: (context, enabled) => GroupedSwitchRow(
          title: '音量鍵翻頁',
          value: enabled,
          onChanged: settings.setVolumeKeyPage,
        ),
      ),
      if (_shape.value.volumeKey)
        _Watch<bool>(
          listenable: settings,
          select: () => settings.volumeKeyReversed,
          builder: (context, reversed) => GroupedSwitchRow(
            title: '反向：音量上翻到下一頁',
            value: reversed,
            onChanged: settings.setVolumeKeyReversed,
          ),
        ),
    ],
  );

  /// 朗讀時畫面跟著念到的句子捲動。
  GroupedSection tts() => GroupedSection(
    margin: margin,
    header: '朗讀',
    children: [
      _Watch<bool>(
        listenable: settings,
        select: () => settings.ttsFollow,
        builder: (context, follow) => GroupedSwitchRow(
          title: '畫面跟著朗讀捲動',
          value: follow,
          onChanged: settings.setTtsFollow,
        ),
      ),
    ],
  );
}

typedef _Shape = ({bool footer, bool statusBarHidden, bool volumeKey});

enum _TypographyField {
  fontSize,
  titleFontSize,
  titleSpacing,
  lineHeight,
  letterSpacing,
  paragraphSpacing,
  chapterSpacing,
  textIndent;

  double read(ReaderV2SettingsController s) => switch (this) {
    fontSize => s.fontSize,
    titleFontSize => s.titleFontSize,
    titleSpacing => s.titleSpacing,
    lineHeight => s.lineHeight,
    letterSpacing => s.letterSpacing,
    paragraphSpacing => s.paragraphSpacing,
    chapterSpacing => s.chapterSpacing,
    textIndent => s.textIndent.toDouble(),
  };

  double defaultIn(ReaderV2PrefsSnapshot d) => switch (this) {
    fontSize => d.fontSize,
    titleFontSize => d.titleFontSize,
    titleSpacing => d.titleSpacing,
    lineHeight => d.lineHeight,
    letterSpacing => d.letterSpacing,
    paragraphSpacing => d.paragraphSpacing,
    chapterSpacing => d.chapterSpacing,
    textIndent => d.textIndent.toDouble(),
  };
}

enum _PaddingField {
  lineChars,
  top,
  bottom;

  double read(ReaderV2SettingsController s) => switch (this) {
    lineChars => s.lineChars.toDouble(),
    top => s.paddingTop,
    bottom => s.paddingBottom,
  };
}

/// 步進器顯示的值與還沒提交的步進。每個欄位一個 [ValueNotifier]，列只聽
/// 自己那一個；有步進時 [_commitDelay] 內沒有再按才一次提交。設定從別處
/// 改了（例如恢復預設），沒有暫存的欄位跟著更新。整體在暫存或顯示值改變時
/// 通知（給「恢復預設」看）。
class _StagedEdits<F extends Enum> extends ChangeNotifier {
  _StagedEdits(
    this._settings, {
    required List<F> fields,
    required double Function(F field) read,
    required this._commit,
  }) : _read = read,
       _values = {
         for (final field in fields) field: ValueNotifier(read(field)),
       } {
    _settings.addListener(_sync);
  }

  static const _commitDelay = Duration(milliseconds: 120);

  final ReaderV2SettingsController _settings;
  final double Function(F field) _read;
  final void Function(Map<F, double> values) _commit;
  final Map<F, ValueNotifier<double>> _values;
  final Set<F> _dirty = <F>{};
  Timer? _timer;

  ValueListenable<double> listenableOf(F field) => _values[field]!;

  double valueOf(F field) => _values[field]!.value;

  bool get hasPending => _dirty.isNotEmpty;

  void stage(F field, double value) {
    _values[field]!.value = value;
    _dirty.add(field);
    _timer?.cancel();
    _timer = Timer(_commitDelay, commitNow);
    notifyListeners();
  }

  void commitNow() {
    _timer?.cancel();
    _timer = null;
    if (_dirty.isEmpty) return;
    final values = {for (final field in _dirty) field: _values[field]!.value};
    _dirty.clear();
    _commit(values);
    notifyListeners();
  }

  /// 丟掉還沒提交的步進，顯示回到設定裡的值。
  void discard() {
    _timer?.cancel();
    _timer = null;
    _dirty.clear();
    _sync();
  }

  void _sync() {
    for (final MapEntry(key: field, value: notifier) in _values.entries) {
      if (!_dirty.contains(field)) notifier.value = _read(field);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _settings.removeListener(_sync);
    commitNow();
    for (final notifier in _values.values) {
      notifier.dispose();
    }
    super.dispose();
  }
}

/// 數值步進列放進卡片時只補列的左右內距；高度由步進列本身決定。
const EdgeInsets _stepperPadding = EdgeInsets.symmetric(
  horizontal: AppGrouped.rowPadding,
);

class _StepperRow extends StatelessWidget implements GroupedSkeletonItem {
  const _StepperRow(this.stepper);

  final Widget stepper;

  /// 骨架照補了左右內距之後的寬度與現在的數值算。
  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) => GroupedItemShape.of(
    stepper,
    context: context,
    width: width - _stepperPadding.horizontal,
  ).padded(_stepperPadding);

  @override
  Widget build(BuildContext context) =>
      GroupedContent(padding: _stepperPadding, child: stepper);
}

/// 暫存提交的步進列：顯示 [_StagedEdits] 裡的值，按了先暫存。
class _StagedStepper<F extends Enum> extends StatelessWidget
    implements GroupedSkeletonItem {
  const _StagedStepper({
    required this.edits,
    required this.field,
    required this.label,
    required this.min,
    required this.max,
    required this.step,
    this.fractionDigits = 0,
    this.trimZeroFraction = false,
    this.unit = '',
    this.maxOf,
    this.listenable,
  });

  final _StagedEdits<F> edits;
  final F field;
  final String label;
  final double min;
  final double max;
  final double step;
  final int fractionDigits;
  final bool trimZeroFraction;
  final String unit;

  /// 這個畫面上能調到的上限（例如放得下的字數），比 [max] 小時取它；值比
  /// 它大時顯示它。
  final double Function(BuildContext context)? maxOf;

  /// [maxOf] 依據的設定；它通知時重算上限。
  final Listenable? listenable;

  NumberStepperRow _row(BuildContext context, double value) {
    var hi = max;
    final limit = maxOf?.call(context);
    if (limit != null && limit >= step) hi = math.min(max, limit);
    return NumberStepperRow(
      label: label,
      value: value,
      min: math.min(min, hi - step),
      max: hi,
      step: step,
      fractionDigits: fractionDigits,
      trimZeroFraction: trimZeroFraction,
      unit: unit,
      onChanged: (next) => edits.stage(field, next),
    );
  }

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) => _row(context, edits.listenableOf(field).value)
      .skeletonShape(context, width: width - _stepperPadding.horizontal)
      .padded(_stepperPadding);

  @override
  Widget build(BuildContext context) {
    final value = edits.listenableOf(field);
    return _StepperRow(
      ListenableBuilder(
        listenable: Listenable.merge([value, ?listenable]),
        builder: (context, _) => _row(context, value.value),
      ),
    );
  }
}

/// 只在 [select] 取出的值變了才重建：設定的控制器任何一項變動都會通知，
/// 每一列只看自己顯示的那一項。
class _Watch<T> extends StatefulWidget implements GroupedSkeletonItem {
  const _Watch({
    required this.listenable,
    required this.select,
    required this.builder,
  });

  final Listenable listenable;
  final T Function() select;
  final Widget Function(BuildContext context, T value) builder;

  /// 骨架照現在的值建出來的那一列。
  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) => GroupedItemShape.of(
    builder(context, select()),
    context: context,
    width: width,
  );

  @override
  State<_Watch<T>> createState() => _WatchState<T>();
}

class _WatchState<T> extends State<_Watch<T>> {
  late T _value = widget.select();

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(_Watch<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
    _value = widget.select();
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final next = widget.select();
    if (next != _value) setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

/// 組標題右側的「恢復預設」。
class _ResetButton extends StatelessWidget implements GroupedSkeletonItem {
  const _ResetButton({required this.onPressed});

  final VoidCallback? onPressed;

  static const String _label = '恢復預設';
  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: AppSpacing.xs,
  );

  /// 按鈕沒有底色，骨架只畫字；字樣同按鈕的 labelLarge。
  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) => GroupedItemShape.text(
    context,
    _label,
    style: Theme.of(context).textTheme.labelLarge!,
    width: double.infinity,
  ).padded(_padding);

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: _padding,
        minimumSize: Size.zero,
        // 字級沿用預設的 labelLarge（主題裡就是 uiSm），自己帶 textStyle
        // 會蓋掉主題的字族。
      ),
      child: const Text(_label),
    );
  }
}

/// 卡片內「左側標籤、右側控件」的一列。
class _LabeledRow extends StatelessWidget implements GroupedSkeletonItem {
  const _LabeledRow({required this.label, required this.child});

  final String label;
  final Widget child;

  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: AppGrouped.rowPadding,
    vertical: AppSpacing.xs,
  );
  static const double _minHeight = AppGrouped.rowMinHeight - AppSpacing.xs * 2;
  static final TextStyle _labelStyle = AppTextStyles.bodyBase.copyWith(
    height: 1.3,
  );

  /// 標籤靠左；控件照它本身的大小靠右，放不下時和 build 一樣等比縮小。
  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) {
    final inner = width - _padding.horizontal;
    final label = GroupedItemShape.text(
      context,
      this.label,
      style: _labelStyle,
      width: inner,
    );
    final control = groupedPartShape(child, context);
    final room = inner - label.width! - AppSpacing.md;
    final scale = math.min(1.0, room / control.width!);
    final height = math.max(
      _minHeight,
      math.max(label.height, control.height * scale),
    );
    final controlLeft = inner - control.width! * scale;
    final controlTop = (height - control.height * scale) / 2;
    return GroupedItemShape(
      height,
      marks: [
        ...label.marksAt(Offset(0, (height - label.height) / 2)),
        for (final mark in control.marks)
          SkeletonShape(
            Rect.fromLTRB(
              controlLeft + mark.rect.left * scale,
              controlTop + mark.rect.top * scale,
              controlLeft + mark.rect.right * scale,
              controlTop + mark.rect.bottom * scale,
            ),
            radius: mark.radius * scale,
          ),
      ],
    ).padded(_padding);
  }

  @override
  Widget build(BuildContext context) {
    return GroupedContent(
      padding: _padding,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _minHeight),
        child: Row(
          children: [
            Text(
              label,
              style: _labelStyle.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // 窄螢幕放不下時整個控件等比縮小，不溢出卡片。
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(fit: BoxFit.scaleDown, child: child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoItemPickerRow extends StatelessWidget
    implements GroupedSkeletonItem {
  const _InfoItemPickerRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final ReaderV2InfoItem value;
  final ValueChanged<ReaderV2InfoItem> onChanged;

  GroupedRow _row(BuildContext context) => GroupedRow(
    title: label,
    value: value.label,
    onTap: () => _showPicker(context),
  );

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) => _row(context).skeletonShape(context, width: width);

  @override
  Widget build(BuildContext context) => _row(context);

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

/// 九宮格：每格是那一區點下去的功能，點一格換功能。
class _ClickActionGrid extends StatelessWidget implements GroupedSkeletonItem {
  const _ClickActionGrid({required this.actions, required this.onChanged});

  final List<int> actions;
  final void Function(int zone, int action) onChanged;

  static const int _columns = 3;
  static const double _aspectRatio = 1.6;
  static const double _gap = AppSpacing.sm;

  /// 九格各畫一塊，和格子一樣大。
  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) {
    final cellWidth = (width - _gap * (_columns - 1)) / _columns;
    final cellHeight = cellWidth / _aspectRatio;
    const rows = 9 ~/ _columns;
    return GroupedItemShape(
      rows * cellHeight + (rows - 1) * _gap,
      marks: [
        for (var i = 0; i < 9; i++)
          SkeletonShape(
            Rect.fromLTWH(
              (i % _columns) * (cellWidth + _gap),
              (i ~/ _columns) * (cellHeight + _gap),
              cellWidth,
              cellHeight,
            ),
            radius: AppRadius.cardMd,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        childAspectRatio: _aspectRatio,
        crossAxisSpacing: _gap,
        mainAxisSpacing: _gap,
      ),
      itemCount: 9,
      itemBuilder: (context, index) {
        final label = ReaderV2TapAction.fromCode(actions[index]).label;
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
                    color: colorScheme.primary.withValues(alpha: 0.6),
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
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.uiSm.copyWith(
                    color: isCenter
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                    fontWeight: isCenter ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showActionPicker(BuildContext context, int zone) async {
    final current = actions[zone];
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
    if (picked != null) onChanged(zone, picked.code);
  }
}
