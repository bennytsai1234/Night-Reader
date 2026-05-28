import 'package:flutter/material.dart';

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
    return Row(
      children: [
        SizedBox(
          width: 65,
          child: Text(label, style: const TextStyle(fontSize: 12)),
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
          width: 35,
          child: Text(
            valueFormatter?.call(value) ?? value.toStringAsFixed(1),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  static Widget buildChoiceChip<T>({
    required String label,
    required T value,
    required T groupValue,
    required Function(T) onSelected,
  }) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: groupValue == value,
      onSelected: (s) => s ? onSelected(value) : null,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
