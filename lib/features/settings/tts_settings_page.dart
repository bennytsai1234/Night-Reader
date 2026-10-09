import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/core/services/tts_service.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/number_stepper_row.dart';

class TtsSettingsPage extends StatelessWidget {
  const TtsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tts = TTSService();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: '朗讀與語音'),
      body: ListenableBuilder(
        listenable: tts,
        builder: (context, child) {
          final engines = tts.engines;
          final voices = [
            ...tts.voices,
          ]..sort((a, b) => tts.voiceLabelOf(a).compareTo(tts.voiceLabelOf(b)));
          final selectedEngine = engines.contains(tts.selectedEngine)
              ? tts.selectedEngine ?? ''
              : '';
          final selectedVoice =
              voices.any(
                (voice) => tts.voiceKeyOf(voice) == tts.selectedVoiceKey,
              )
              ? tts.selectedVoiceKey ?? ''
              : '';
          final voiceOptions = <_Choice>[
            const _Choice('', _systemDefault),
            for (final voice in voices)
              _Choice(tts.voiceKeyOf(voice), tts.voiceLabelOf(voice)),
          ];
          final engineOptions = <_Choice>[
            const _Choice('', _systemDefault),
            for (final engine in engines) _Choice(engine, engine),
          ];

          return GroupedListView(
            children: [
              GroupedSection(
                header: '朗讀參數',
                children: [
                  _stepper(
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
                  ),
                  _stepper(
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
                  ),
                  _stepper(
                    NumberStepperRow(
                      label: '音量',
                      value: tts.volume,
                      min: TTSService.minVolume,
                      max: TTSService.maxVolume,
                      step: TTSService.volumeStep,
                      displayScale: 100,
                      unit: '%',
                      onChanged: (value) =>
                          _reportSaveFailure(context, tts.setVolume(value)),
                    ),
                  ),
                ],
              ),
              GroupedSection(
                header: '系統語音',
                children: [
                  GroupedRow(
                    title: '語音引擎',
                    value: _labelOf(engineOptions, selectedEngine),
                    onTap: () async {
                      final value = await _pick(
                        context,
                        title: '語音引擎',
                        options: engineOptions,
                        selected: selectedEngine,
                      );
                      if (value == null) return;
                      try {
                        await tts.setEngine(value.isEmpty ? null : value);
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('語音引擎切換失敗，已維持原設定')),
                        );
                      }
                    },
                  ),
                  GroupedRow(
                    title: '音色',
                    value: _labelOf(voiceOptions, selectedVoice),
                    enabled: voices.isNotEmpty,
                    onTap: voices.isEmpty
                        ? null
                        : () async {
                            final value = await _pick(
                              context,
                              title: '音色',
                              options: voiceOptions,
                              selected: selectedVoice,
                            );
                            if (value == null) return;
                            try {
                              await tts.setVoiceByKey(
                                value.isEmpty ? null : value,
                              );
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('音色無法套用，請改選其他音色')),
                              );
                            }
                          },
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

const String _systemDefault = '系統預設';

/// 數值步進列放進卡片時補上列的左右內距。
Widget _stepper(Widget row) => GroupedContent(
  padding: const EdgeInsets.symmetric(horizontal: AppGrouped.rowPadding),
  child: row,
);

/// 選擇頁的一個選項；[key] 為空字串代表「系統預設」。
class _Choice {
  const _Choice(this.key, this.label);

  final String key;
  final String label;
}

String _labelOf(List<_Choice> options, String key) {
  for (final option in options) {
    if (option.key == key) return option.label;
  }
  return _systemDefault;
}

/// 以 Telegram 式的單選清單頁取代下拉選單；回傳選中的 key，返回則為 null。
Future<String?> _pick(
  BuildContext context, {
  required String title,
  required List<_Choice> options,
  required String selected,
}) {
  return Navigator.push<String>(
    context,
    MaterialPageRoute(
      builder: (_) =>
          _ChoicePage(title: title, options: options, selected: selected),
    ),
  );
}

class _ChoicePage extends StatelessWidget {
  const _ChoicePage({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<_Choice> options;
  final String selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassNavHeader(title: title),
      body: GroupedListView(
        children: [
          GroupedSection(
            children: [
              for (final option in options)
                GroupedCheckRow(
                  title: option.label,
                  selected: option.key == selected,
                  onTap: () => Navigator.pop(context, option.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 參數保存失敗時 TTSService 已把數值還原；這裡只負責告知使用者。
void _reportSaveFailure(BuildContext context, Future<void> save) {
  unawaited(
    save.catchError((Object _) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('朗讀設定儲存失敗，已恢復原本的值')));
    }),
  );
}
