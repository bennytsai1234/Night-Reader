import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/services/tts_service.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/number_stepper_row.dart';

abstract class ReaderV2TtsSheetController extends Listenable {
  bool get isPlaying;
  double get rate;
  double get pitch;

  Future<void> toggle();
  Future<void> stop();
  Future<void> setRate(double value);
  Future<void> setPitch(double value);
}

/// 閱讀器內的朗讀面板內容；由 ReaderV2MenuSheet 以選單配色開啟。
class ReaderV2TtsPanel extends StatelessWidget {
  const ReaderV2TtsPanel({super.key, required this.tts});

  final ReaderV2TtsSheetController tts;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tts,
      builder: (context, _) {
        return AppBottomSheet(
          title: '朗讀',
          icon: Icons.record_voice_over,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(tts.isPlaying ? Icons.pause : Icons.play_arrow),
              title: Text(
                tts.isPlaying ? '暫停朗讀' : '從目前位置朗讀',
                style: AppTextStyles.uiMd,
              ),
              onTap: () => unawaited(tts.toggle()),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.stop),
              title: const Text('停止', style: AppTextStyles.uiMd),
              onTap: () => unawaited(tts.stop()),
            ),
            const SheetSection(title: '朗讀參數'),
            NumberStepperRow(
              label: '語速',
              value: tts.rate,
              min: TTSService.minRate,
              max: TTSService.maxRate,
              step: TTSService.rateStep,
              fractionDigits: 1,
              unit: 'x',
              onChanged: (value) =>
                  _reportSaveFailure(context, tts.setRate(value)),
            ),
            NumberStepperRow(
              label: '音調',
              value: tts.pitch,
              min: TTSService.minPitch,
              max: TTSService.maxPitch,
              step: TTSService.pitchStep,
              fractionDigits: 1,
              onChanged: (value) =>
                  _reportSaveFailure(context, tts.setPitch(value)),
            ),
          ],
        );
      },
    );
  }
}

/// 參數保存失敗時 TTSService 已把數值還原；這裡只負責告知使用者。
void _reportSaveFailure(BuildContext context, Future<void> save) {
  unawaited(
    save.catchError((Object _) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('朗讀設定儲存失敗，已恢復原本的值')),
      );
    }),
  );
}
