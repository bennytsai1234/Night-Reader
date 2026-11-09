import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/services/sleep_timer.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass_segmented.dart';
import 'package:night_reader/shared/widgets/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/number_stepper_row.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

/// 定時關閉的選項與倒數，朗讀面板與有聲書播放器共用。倒數不靠定時器逐秒
/// 通知，這裡自己每秒重讀剩餘時間，只重建這一小塊。
class SleepTimerSection extends StatefulWidget implements GroupedSkeletonItem {
  const SleepTimerSection({super.key, required this.timer});

  final SleepTimer timer;

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) {
    // 分段控制的軌道、自訂分鐘的步進列與倒數文字，各自照元件本身的高度。
    var height = GlassSegmented.trackHeight;
    final marks = <SkeletonShape>[
      SkeletonShape(
        Rect.fromLTWH(0, 0, width, height),
        radius: AppRadius.pillShape,
      ),
    ];
    if (timer.option == SleepTimerOption.custom) {
      final stepper = _SleepTimerSectionState._customStepper(timer)
          .skeletonShape(context, width: width);
      marks.addAll(stepper.marksAt(Offset(0, height)));
      height += stepper.height;
    }
    final status = _SleepTimerSectionState._status(timer);
    if (status != null) {
      final text = GroupedItemShape.text(
        context,
        status,
        style: _SleepTimerSectionState.statusStyle,
        width: width,
      );
      height += _SleepTimerSectionState.statusGap;
      for (final mark in text.marks) {
        marks.add(
          SkeletonShape(
            mark.rect.shift(Offset((width - mark.rect.width) / 2, height)),
          ),
        );
      }
      height += text.height;
    }
    return GroupedItemShape(height, marks: marks);
  }

  @override
  State<SleepTimerSection> createState() => _SleepTimerSectionState();
}

class _SleepTimerSectionState extends State<SleepTimerSection> {
  /// 倒數文字的字樣與上方間距；骨架照同一份排。
  static const TextStyle statusStyle = AppTextStyles.labelSm;
  static const double statusGap = AppSpacing.sm;

  static NumberStepperRow _customStepper(SleepTimer timer) => NumberStepperRow(
    label: '分鐘',
    value: timer.customMinutes.toDouble(),
    min: SleepTimer.minCustomMinutes.toDouble(),
    max: SleepTimer.maxCustomMinutes.toDouble(),
    step: 1,
    onChanged: (value) => unawaited(timer.setCustomMinutes(value.round())),
  );

  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.timer.remaining != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.timer,
      builder: (context, _) {
        final timer = widget.timer;
        final status = _status(timer);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlassSegmented<SleepTimerOption>(
              dense: true,
              segments: [
                for (final option in SleepTimerOption.values)
                  GlassSegment(option, option.label),
              ],
              selected: timer.option,
              onChanged: (option) => unawaited(timer.choose(option)),
            ),
            if (timer.option == SleepTimerOption.custom) _customStepper(timer),
            if (status != null)
              Padding(
                padding: const EdgeInsets.only(top: statusGap),
                child: Text(
                  status,
                  textAlign: TextAlign.center,
                  style: statusStyle.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static String? _status(SleepTimer timer) {
    final remaining = timer.remaining;
    if (remaining == null) return null;
    // 無條件進位到秒，剛開始倒數時顯示整數分鐘。
    final seconds = (remaining.inMilliseconds + 999) ~/ 1000;
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss 後暫停';
  }
}
