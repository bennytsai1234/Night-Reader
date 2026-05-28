import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader/features/reader_v2/features/settings/reader_v2_setting_components.dart';
import 'package:reader/shared/widgets/app_bottom_sheet.dart';

abstract class ReaderV2TtsSheetController extends Listenable {
  bool get isPlaying;
  double get rate;
  double get pitch;

  Future<void> toggle();
  Future<void> stop();
  Future<void> setRate(double value);
  Future<void> setPitch(double value);
}

class ReaderV2TtsSheet {
  const ReaderV2TtsSheet._();

  static void show(
    BuildContext context, {
    required ReaderV2TtsSheetController tts,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReaderTtsSheet(tts: tts),
    );
  }
}

class _ReaderTtsSheet extends StatelessWidget {
  const _ReaderTtsSheet({required this.tts});

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
              title: Text(tts.isPlaying ? '暫停朗讀' : '從目前位置朗讀'),
              onTap: () => unawaited(tts.toggle()),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.stop),
              title: const Text('停止'),
              onTap: () => unawaited(tts.stop()),
            ),
            ReaderV2SettingComponents.buildSliderRow(
              label: '語速',
              value: tts.rate,
              min: 0.5,
              max: 1.5,
              onChanged: (value) {
                unawaited(tts.setRate(value));
              },
            ),
            ReaderV2SettingComponents.buildSliderRow(
              label: '音調',
              value: tts.pitch,
              min: 0.5,
              max: 1.5,
              onChanged: (value) {
                unawaited(tts.setPitch(value));
              },
            ),
          ],
        );
      },
    );
  }
}
