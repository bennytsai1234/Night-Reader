import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_haptics.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/press_ink.dart';

/// 數值設定列：`標籤 [−] 數值 [+]`。
///
/// - 點擊 −／+ 以 [step] 為單位調整，長按連續調整。
/// - 點擊數值開啟輸入框，直接輸入目標值。
///
/// 所有輸出值都會對齊 `min + n * step` 的格點並限制在 `[min, max]` 內，
/// 呼叫端不會收到拖動條那種任意小數。
///
/// 本身不帶左右內距、高度約為分組清單單行列（44）；放進分組卡片時以
/// `GroupedContent` 提供列內距。
class NumberStepperRow extends StatefulWidget {
  const NumberStepperRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.fractionDigits = 0,
    this.displayScale = 1,
    this.unit = '',
    this.trimZeroFraction = false,
  }) : assert(min < max),
       assert(step > 0),
       assert(displayScale > 0);

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;

  /// 顯示與輸入時保留的小數位數（以顯示單位計）。
  final int fractionDigits;

  /// 儲存值轉顯示值的倍率，例如 0.12 以 `12%` 呈現時為 100。
  final double displayScale;

  /// 顯示單位，例如 `%`、`倍`；除了 `%` 都和數字隔一格。
  final String unit;

  /// 數值剛好是整數時不寫小數（18、18.5），而不是固定 [fractionDigits] 位。
  final bool trimZeroFraction;

  /// 數字接上單位：`%` 緊貼，其他單位隔一格（`1.5 倍`、`2 行`）。
  static String withUnit(String number, String unit) {
    if (unit.isEmpty) return number;
    return unit == '%' ? '$number%' : '$number $unit';
  }

  /// 將任意值對齊到 [step] 格點並限制在範圍內。
  static double snap(double value, double min, double max, double step) {
    if (!value.isFinite) return min;
    final steps = ((value - min) / step).round();
    final snapped = min + steps * step;
    // 以格點精度四捨五入，消除浮點累積誤差（例如 1.2000000000000002）。
    final decimals = _decimalsOf(step) + _decimalsOf(min);
    final factor = math.pow(10, decimals).toDouble();
    final rounded = (snapped * factor).round() / factor;
    return rounded.clamp(min, max).toDouble();
  }

  static int _decimalsOf(double value) {
    var decimals = 0;
    var v = value.abs();
    while (decimals < 6 && (v - v.roundToDouble()).abs() > 1e-9) {
      v *= 10;
      decimals += 1;
    }
    return decimals;
  }

  @override
  State<NumberStepperRow> createState() => _NumberStepperRowState();
}

class _NumberStepperRowState extends State<NumberStepperRow> {
  static const _repeatInterval = Duration(milliseconds: 90);

  Timer? _repeatTimer;
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = _normalized(widget.value);
  }

  @override
  void didUpdateWidget(NumberStepperRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 長按連續調整期間以本地值為準，避免外部延遲提交把數值拉回。
    if (_repeatTimer == null) {
      _value = _normalized(widget.value);
    }
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    super.dispose();
  }

  double _normalized(double value) =>
      NumberStepperRow.snap(value, widget.min, widget.max, widget.step);

  bool get _canDecrease => _value > widget.min;
  bool get _canIncrease => _value < widget.max;

  String _format(double value) {
    final scaled = value * widget.displayScale;
    if (widget.trimZeroFraction && scaled == scaled.roundToDouble()) {
      return scaled.toStringAsFixed(0);
    }
    return scaled.toStringAsFixed(widget.fractionDigits);
  }

  String _withUnit(String number) =>
      NumberStepperRow.withUnit(number, widget.unit);

  String get _displayText => _withUnit(_format(_value));

  void _setValue(double next) {
    final normalized = _normalized(next);
    if (normalized == _value) return;
    setState(() => _value = normalized);
    widget.onChanged(normalized);
  }

  bool _stepBy(int direction) {
    final before = _value;
    _setValue(_value + direction * widget.step);
    return _value != before;
  }

  /// 點一下步進；數值真的變了才給選擇回饋。
  void _tapStep(int direction) {
    if (_stepBy(direction)) AppHaptics.select();
  }

  bool _atLimit(int direction) => direction > 0 ? !_canIncrease : !_canDecrease;

  /// 長按連續步進只在開始與碰到上下限時各回饋一次：每 90ms 一步時每步都震，
  /// 手上是連續的嗡嗡聲，分不出哪一下是重點；碰到上下限那一下告訴使用者
  /// 可以放手了。
  void _startRepeat(int direction) {
    _repeatTimer?.cancel();
    if (!_stepBy(direction)) return;
    AppHaptics.select();
    if (_atLimit(direction)) return;
    _repeatTimer = Timer.periodic(_repeatInterval, (_) {
      if (!mounted || !_stepBy(direction)) {
        _stopRepeat();
      } else if (_atLimit(direction)) {
        AppHaptics.select();
        _stopRepeat();
      }
    });
  }

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  Future<void> _editValue() async {
    final result = await showDialog<double>(
      context: context,
      barrierColor: AppChrome.of(context).barrier,
      builder: (_) => _NumberInputDialog(
        label: widget.label,
        initialText: _format(_value),
        min: widget.min,
        max: widget.max,
        fractionDigits: widget.fractionDigits,
        displayScale: widget.displayScale,
        unit: widget.unit,
        format: _format,
      ),
    );
    if (result != null && mounted) _setValue(result);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final increased = _normalized(_value + widget.step);
    final decreased = _normalized(_value - widget.step);
    return Semantics(
      label: widget.label,
      value: _displayText,
      increasedValue: _canIncrease ? _withUnit(_format(increased)) : null,
      decreasedValue: _canDecrease ? _withUnit(_format(decreased)) : null,
      onIncrease: _canIncrease ? () => _stepBy(1) : null,
      onDecrease: _canDecrease ? () => _stepBy(-1) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  widget.label,
                  style: AppTextStyles.bodyBase.copyWith(
                    height: 1.3,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            _StepButton(
              icon: Icons.remove_rounded,
              tooltip: '減少${widget.label}',
              enabled: _canDecrease,
              onTap: () => _tapStep(-1),
              onLongPressStart: () => _startRepeat(-1),
              onLongPressEnd: _stopRepeat,
            ),
            ExcludeSemantics(
              child: _ValueButton(text: _displayText, onTap: _editValue),
            ),
            _StepButton(
              icon: Icons.add_rounded,
              tooltip: '增加${widget.label}',
              enabled: _canIncrease,
              onTap: () => _tapStep(1),
              onLongPressStart: () => _startRepeat(1),
              onLongPressEnd: _stopRepeat,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    // 原本是 IconButton：每顆各帶一套按鈕樣式解析、主題複本、狀態控制器與
    // 動畫控制器，一列三顆，閱讀偏好一進頁要建二十顆，是那一格最大的一塊。
    // 畫面照 IconButton 的樣子畫：36 的淡墨圓、18 的圖示、按下疊前景色
    // 10%、停用時圖示 38%，點擊範圍是外圍 48×48（Material 的最小點擊範圍）。
    return GestureDetector(
      onLongPressStart: enabled ? (_) => onLongPressStart() : null,
      onLongPressEnd: enabled ? (_) => onLongPressEnd() : null,
      onLongPressCancel: enabled ? onLongPressEnd : null,
      // 不使用 Tooltip：Tooltip 自帶長按手勢，會與連續調整競爭。
      child: Semantics(
        container: true,
        label: tooltip,
        button: true,
        enabled: enabled,
        child: SizedBox.square(
          dimension: _kStepperTapTarget,
          // 按下的淡墨畫在所在卡片的 Material 上、淡墨圓的下面；兩層都是
          // 前景色，疊的順序不影響顏色。
          child: PressInk(
            onTap: enabled ? onTap : null,
            customBorder: const _CenteredCircle(_kStepperControlHeight),
            // 和 IconButton.styleFrom 按下時一樣：前景色 10%。
            highlightColor: onSurface.withValues(alpha: 0.1),
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _controlFill(context),
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: _kStepperControlHeight,
                  child: Icon(
                    icon,
                    size: 18,
                    color: enabled
                        ? onSurface
                        : onSurface.withValues(alpha: 0.38),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 外框中央一個直徑 [diameter] 的圓：步進鈕的點擊範圍是 48×48，按下的
/// 高亮只畫在中間 36 的圓上。
class _CenteredCircle extends ShapeBorder {
  const _CenteredCircle(this.diameter);

  final double diameter;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  Path _circle(Rect rect) =>
      Path()
        ..addOval(Rect.fromCircle(center: rect.center, radius: diameter / 2));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => _circle(rect);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _circle(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => _CenteredCircle(diameter * t);
}

/// 步進鈕與數值鈕的高度；加上列的上下內距約等於分組清單單行列高。
const double _kStepperControlHeight = 36;

/// 步進鈕的點擊範圍（Material 的最小點擊範圍 48×48），也是它佔的大小。
const double _kStepperTapTarget = kMinInteractiveDimension;

/// 步進控件的淡墨底：同時適用 App 分組卡片與閱讀器選單主題的面板。
Color _controlFill(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07);

class _ValueButton extends StatelessWidget {
  const _ValueButton({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Material(
        color: _controlFill(context),
        borderRadius: AppRadius.pillShape,
        child: PressInk(
          onTap: onTap,
          borderRadius: AppRadius.pillShape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 64,
              minHeight: _kStepperControlHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Center(
                widthFactor: 1,
                child: Text(
                  text,
                  style: AppTextStyles.uiMd.copyWith(
                    color: colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NumberInputDialog extends StatefulWidget {
  const _NumberInputDialog({
    required this.label,
    required this.initialText,
    required this.min,
    required this.max,
    required this.fractionDigits,
    required this.displayScale,
    required this.unit,
    required this.format,
  });

  final String label;
  final String initialText;
  final double min;
  final double max;
  final int fractionDigits;
  final double displayScale;
  final String unit;
  final String Function(double value) format;

  @override
  State<_NumberInputDialog> createState() => _NumberInputDialogState();
}

class _NumberInputDialogState extends State<_NumberInputDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initialText.length,
        );
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _rangeText => NumberStepperRow.withUnit(
    '${widget.format(widget.min)}–${widget.format(widget.max)}',
    widget.unit,
  );

  void _submit() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null) {
      setState(() => _errorText = '請輸入數字');
      return;
    }
    final value = parsed / widget.displayScale;
    // 以顯示精度比較，避免 0.45 經倍率換算後的浮點誤差誤判超出範圍。
    const epsilon = 1e-9;
    if (value < widget.min - epsilon || value > widget.max + epsilon) {
      setState(() => _errorText = '超出範圍 $_rangeText');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final allowDecimal = widget.fractionDigits > 0;
    return AppAlert<bool>(
      title: widget.label,
      message: '範圍 $_rangeText',
      onAction: (confirmed) => confirmed ? _submit() : Navigator.pop(context),
      actions: const [
        AppAlertAction(label: '取消', value: false),
        AppAlertAction(label: '確定', value: true, isDefault: true),
      ],
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            allowDecimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
          ),
        ],
        textInputAction: TextInputAction.done,
        onChanged: (_) {
          if (_errorText != null) setState(() => _errorText = null);
        },
        onSubmitted: (_) => _submit(),
        textAlign: TextAlign.center,
        // 和 AlertTextField 一樣用分組底色當欄位底：預設的表面色和提示框
        // 幾乎同色，看不出欄位範圍。
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppChrome.of(context).groupedBackground,
          border: const OutlineInputBorder(
            borderRadius: AppRadius.cardMd,
            borderSide: BorderSide.none,
          ),
          errorText: _errorText,
          suffixText: widget.unit.isEmpty ? null : widget.unit,
        ),
      ),
    );
  }
}
