import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/core/services/tts_service.dart';
import 'package:provider/provider.dart';

import 'settings_provider.dart';

class TtsSettingsPage extends StatelessWidget {
  const TtsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tts = TTSService();

    return Scaffold(
      appBar: AppBar(title: const Text('朗讀與語音')),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return ListenableBuilder(
            listenable: tts,
            builder: (context, child) {
              final engines = tts.engines;
              final voices = [...tts.voices]..sort(
                (a, b) => tts.voiceLabelOf(a).compareTo(tts.voiceLabelOf(b)),
              );
              final selectedEngine =
                  engines.contains(tts.selectedEngine)
                      ? tts.selectedEngine ?? ''
                      : '';
              final selectedVoice =
                  voices.any(
                        (voice) =>
                            tts.voiceKeyOf(voice) == tts.selectedVoiceKey,
                      )
                      ? tts.selectedVoiceKey ?? ''
                      : '';

              return ListTileTheme(
                data: const ListTileThemeData(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                ),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  children: [
                    _buildSectionTitle(context, '朗讀參數'),
                    ListTile(
                      title: const Text('語速'),
                      subtitle: Slider(
                        value: settings.speechRate,
                        min: 0.1,
                        max: 1.0,
                        onChanged: (v) => settings.setSpeechRate(v),
                      ),
                      trailing: Text(settings.speechRate.toStringAsFixed(1)),
                    ),
                    ListTile(
                      title: const Text('音調'),
                      subtitle: Slider(
                        value: settings.speechPitch,
                        min: 0.5,
                        max: 2.0,
                        onChanged: (v) => settings.setSpeechPitch(v),
                      ),
                      trailing: Text(settings.speechPitch.toStringAsFixed(1)),
                    ),
                    ListTile(
                      title: const Text('音量'),
                      subtitle: Slider(
                        value: settings.speechVolume,
                        min: 0.0,
                        max: 1.0,
                        onChanged: (v) => settings.setSpeechVolume(v),
                      ),
                      trailing: Text(settings.speechVolume.toStringAsFixed(1)),
                    ),
                    const Divider(),
                    _buildSectionTitle(context, '系統語音'),
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
                              const SnackBar(
                                content: Text('語音引擎切換失敗，已維持原設定'),
                              ),
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
                        onChanged:
                            voices.isEmpty
                                ? null
                                : (value) async {
                                  try {
                                    await tts.setVoiceByKey(
                                      value == null || value.isEmpty
                                          ? null
                                          : value,
                                    );
                                  } catch (_) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('音色無法套用，請改選其他音色'),
                                      ),
                                    );
                                  }
                                },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Text(
        title,
        style: AppTextStyles.bodySm.copyWith(
          height: 1.3,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
