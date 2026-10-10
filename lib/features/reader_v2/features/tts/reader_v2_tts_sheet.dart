import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/services/tts_service.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_sheet.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_highlight_style.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/number_stepper_row.dart';

abstract class ReaderV2TtsSheetController extends Listenable {
  bool get isPlaying;

  /// 暫停中：播放鍵會從暫停處接著念，而不是從畫面位置開始。
  bool get isPaused;
  double get rate;
  double get pitch;

  Future<void> toggle();
  Future<void> stop();
  Future<void> setRate(double value);
  Future<void> setPitch(double value);
}

/// 閱讀器內的朗讀面板內容；由 ReaderV2MenuSheet 以選單配色開啟。
class ReaderV2TtsPanel extends StatelessWidget {
  const ReaderV2TtsPanel({
    super.key,
    required this.tts,
    required this.settings,
  });

  final ReaderV2TtsSheetController tts;
  final ReaderV2SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[tts, settings]),
      builder: (context, _) {
        return ReaderV2SheetScaffold(
          title: '朗讀',
          children: [
            // 分組卡片，和閱讀器其他面板一致（DESIGN 不再使用 ListTile）。
            GroupedSection(
              margin: EdgeInsets.zero,
              children: [
                GroupedRow(
                  leading: GroupedIconTile(
                    tts.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    tint: AppTint.azurite,
                  ),
                  title: tts.isPlaying
                      ? '暫停朗讀'
                      : tts.isPaused
                      ? '繼續朗讀'
                      : '從目前位置朗讀',
                  showChevron: false,
                  onTap: () => unawaited(tts.toggle()),
                ),
                GroupedRow(
                  leading: const GroupedIconTile(
                    Icons.stop_rounded,
                    tint: AppTint.rust,
                  ),
                  title: '停止',
                  showChevron: false,
                  onTap: () => unawaited(tts.stop()),
                ),
              ],
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
            const SheetSection(title: '朗讀高亮'),
            _HighlightSection(settings: settings),
          ],
        );
      },
    );
  }
}

/// 高亮預覽、色票與深淺。拖動深淺時只更新面板內的暫存值與預覽，放開才
/// 寫入偏好：每一格都寫入會連帶整個閱讀器重建。
class _HighlightSection extends StatefulWidget {
  const _HighlightSection({required this.settings});

  final ReaderV2SettingsController settings;

  @override
  State<_HighlightSection> createState() => _HighlightSectionState();
}

class _HighlightSectionState extends State<_HighlightSection> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final strength = _dragging ?? settings.highlightStrength;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HighlightPreview(settings: settings, strength: strength),
        const SizedBox(height: AppSpacing.md),
        _HighlightColorRow(settings: settings),
        Row(
          children: [
            const ExcludeSemantics(
              child: Text('深淺', style: AppTextStyles.uiMd),
            ),
            Expanded(
              child: Semantics(
                label: '高亮深淺',
                child: Slider(
                  value: strength,
                  min: ReaderV2HighlightStrength.min,
                  max: ReaderV2HighlightStrength.max,
                  onChanged: (value) => setState(() => _dragging = value),
                  onChangeEnd: (value) {
                    setState(() => _dragging = null);
                    settings.setHighlightStrength(value);
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 一段以目前閱讀配色呈現的範例文字，中間一句套用高亮；調整顏色與
/// 深淺時即時反映。
class _HighlightPreview extends StatelessWidget {
  const _HighlightPreview({required this.settings, required this.strength});

  final ReaderV2SettingsController settings;

  /// 預覽用的深淺；拖動中是尚未寫入的暫存值。
  final double strength;

  @override
  Widget build(BuildContext context) {
    final palette = StylePalette.of(context);
    final style = TextStyle(
      color: palette.readerText,
      fontSize: 17,
      height: 1.6,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.readerBackground,
        borderRadius: AppRadius.cardMd,
      ),
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            const TextSpan(text: '夜深了，屋外的雨聲漸漸停歇。'),
            TextSpan(
              text: '他放下手中的書，望向窗外的月光。',
              style: TextStyle(
                background: Paint()
                  ..color = settings.highlightColor
                      .resolve(palette)
                      .withValues(alpha: strength),
              ),
            ),
            const TextSpan(text: '遠處傳來幾聲犬吠。'),
          ],
        ),
      ),
    );
  }
}

class _HighlightColorRow extends StatelessWidget {
  const _HighlightColorRow({required this.settings});

  final ReaderV2SettingsController settings;

  static const double _swatchSize = 30;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = StylePalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final option in ReaderV2HighlightColor.values)
          Semantics(
            button: true,
            selected: option == settings.highlightColor,
            label: option.label,
            // 色票下方的文字和這個標籤相同，排除子樹才不會念兩次；點擊動作
            // 也跟著被排除，要在這裡補上。
            excludeSemantics: true,
            onTap: () => settings.setHighlightColor(option),
            child: InkResponse(
              onTap: () => settings.setHighlightColor(option),
              radius: _swatchSize,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: _swatchSize,
                    height: _swatchSize,
                    decoration: BoxDecoration(
                      color: option.resolve(palette),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: option == settings.highlightColor
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width: option == settings.highlightColor ? 2.5 : 1,
                      ),
                    ),
                    child: option == settings.highlightColor
                        ? Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: Colors.black.withValues(alpha: 0.7),
                          )
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(option.label, style: AppTextStyles.labelSm),
                ],
              ),
            ),
          ),
      ],
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
