import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/settings_section_title.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/core/services/tts_service.dart';
import 'package:night_reader/shared/widgets/number_stepper_row.dart';

class TtsSettingsPage extends StatelessWidget {
  const TtsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tts = TTSService();

    return Scaffold(
      appBar: AppBar(title: const Text('朗讀與語音')),
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

          return ListTileTheme(
            data: const ListTileThemeData(
              contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
            ),
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              children: [
                const SettingsSectionTitle(''),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Column(
                    children: [
                      NumberStepperRow(
                        label: '語速',
                        value: tts.rate,
                        min: TTSService.minRate,
                        max: TTSService.maxRate,
                        step: 0.1,
                        fractionDigits: 1,
                        onChanged: (value) => unawaited(tts.setRate(value)),
                      ),
                      NumberStepperRow(
                        label: '音調',
                        value: tts.pitch,
                        min: TTSService.minPitch,
                        max: TTSService.maxPitch,
                        step: 0.1,
                        fractionDigits: 1,
                        onChanged: (value) => unawaited(tts.setPitch(value)),
                      ),
                      NumberStepperRow(
                        label: '音量',
                        value: tts.volume,
                        min: TTSService.minVolume,
                        max: TTSService.maxVolume,
                        step: 0.05,
                        displayScale: 100,
                        unit: '%',
                        onChanged: (value) => unawaited(tts.setVolume(value)),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                const SettingsSectionTitle(''),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('engine-$selectedEngine'),
                    initialValue: selectedEngine,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '語音引擎',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('系統預設'),
                      ),
                      ...engines.map(
                        (engine) => DropdownMenuItem<String>(
                          value: engine,
                          child: Text(
                            engine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) async {
                      try {
                        await tts.setEngine(
                          value == null || value.isEmpty ? null : value,
                        );
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('語音引擎切換失敗，已維持原設定')),
                        );
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('voice-$selectedVoice-${voices.length}'),
                    initialValue: selectedVoice,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '音色',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('系統預設'),
                      ),
                      ...voices.map(
                        (voice) => DropdownMenuItem<String>(
                          value: tts.voiceKeyOf(voice),
                          child: Text(
                            tts.voiceLabelOf(voice),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: voices.isEmpty
                        ? null
                        : (value) async {
                            try {
                              await tts.setVoiceByKey(
                                value == null || value.isEmpty ? null : value,
                              );
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('音色無法套用，請改選其他音色')),
                              );
                            }
                          },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
