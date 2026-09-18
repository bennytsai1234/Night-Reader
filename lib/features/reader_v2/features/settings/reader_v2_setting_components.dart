import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';

class ReaderV2SettingComponents {
  static Widget buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required Function(double) onChanged,
    Function(double)? onChangeEnd,
    int? divisions,
    String Function(double value)? valueFormatter,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 65,
            child: Text(
              label,
              style: AppTextStyles.bodySm.copyWith(height: 1.3),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              valueFormatter?.call(value) ?? value.toStringAsFixed(1),
              textAlign: TextAlign.end,
              style: AppTextStyles.labelSm.copyWith(
                height: 1.3,
                color: Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget buildChoiceChip<T>({
    required String label,
    required T value,
    required T groupValue,
    required Function(T) onSelected,
  }) {
    return ChoiceChip(
      label: Text(label, style: AppTextStyles.bodySm.copyWith(height: 1.2)),
      selected: groupValue == value,
      onSelected: (s) => s ? onSelected(value) : null,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
