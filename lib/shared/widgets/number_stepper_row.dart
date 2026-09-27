import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 數值設定列：`標籤 [−] 數值 [+]`。
///
/// - 點擊 −／+ 以 [step] 為單位調整，長按連續調整。
/// - 點擊數值開啟輸入框，直接輸入目標值。
///
/// 所有輸出值都會對齊 `min + n * step` 的格點並限制在 `[min, max]` 內，
/// 呼叫端不會收到拖動條那種任意小數。
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

  /// 顯示單位，例如 `%`、`x`。
  final String unit;

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

  String _format(double value) =>
      (value * widget.displayScale).toStringAsFixed(widget.fractionDigits);

  String get _displayText => '${_format(_value)}${widget.unit}';

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

  void _startRepeat(int direction) {
    _repeatTimer?.cancel();
    if (!_stepBy(direction)) return;
    _repeatTimer = Timer.periodic(_repeatInterval, (_) {
      if (!mounted || !_stepBy(direction)) _stopRepeat();
    });
  }

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  Future<void> _editValue() async {
    final result = await showDialog<double>(
      context: context,
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
      increasedValue: _canIncrease
          ? '${_format(increased)}${widget.unit}'
          : null,
      decreasedValue: _canDecrease
          ? '${_format(decreased)}${widget.unit}'
          : null,
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
                  style: AppTextStyles.uiMd.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            _StepButton(
              icon: Icons.remove_rounded,
              tooltip: '減少${widget.label}',
              enabled: _canDecrease,
              onTap: () => _stepBy(-1),
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
              onTap: () => _stepBy(1),
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
    return GestureDetector(
      onLongPressStart: enabled ? (_) => onLongPressStart() : null,
      onLongPressEnd: enabled ? (_) => onLongPressEnd() : null,
      onLongPressCancel: enabled ? onLongPressEnd : null,
      // 不使用 IconButton.tooltip：Tooltip 自帶長按手勢，會與連續調整競爭。
      child: Semantics(
        label: tooltip,
        child: IconButton.outlined(
          onPressed: enabled ? onTap : null,
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon),
        ),
      ),
    );
  }
}

class _ValueButton extends StatelessWidget {
  const _ValueButton({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: AppRadius.cardMd,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.cardMd,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 64, minHeight: 40),
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

  String get _rangeText =>
      '${widget.format(widget.min)}–${widget.format(widget.max)}${widget.unit}';

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
    return AlertDialog(
      title: Text(widget.label),
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
        decoration: InputDecoration(
          helperText: '範圍 $_rangeText',
          errorText: _errorText,
          suffixText: widget.unit.isEmpty ? null : widget.unit,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('確定')),
      ],
    );
  }
}
