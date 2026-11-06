import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/core/models/source/source_login_ui.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

/// 登入表單的按鈕間距。
const double kSourceLoginButtonGap = AppSpacing.sm;

/// 一顆按鈕在一列裡的位置。
typedef SourceLoginButtonSlot = ({int index, double width});

/// 照 Legado（Android FlexboxLayout，可換行）排一串按鈕：每顆的基本寬是
/// [SourceLoginRowStyle.basisPercent] × 整列寬（負數照字寬 [intrinsic]），
/// 放不下就換行（`wrapBefore` 一定換），同一列剩下的寬照 `grow` 攤、超出的
/// 照 `shrink` 扣。按鈕之間空 [gap]，所以四顆 25% 的放不下一列，和 Legado
/// 一樣三顆一列。
List<List<SourceLoginButtonSlot>> layoutSourceLoginButtons(
  List<SourceLoginRow> buttons,
  double width, {
  required double Function(SourceLoginRow button) intrinsic,
  double gap = kSourceLoginButtonGap,
}) {
  final lines = <List<(int, double)>>[];
  var line = <(int, double)>[];
  var used = 0.0;
  for (final (index, button) in buttons.indexed) {
    final percent = button.style.basisPercent;
    final basis = math.min(
      width,
      percent >= 0 ? percent * width : intrinsic(button),
    );
    final need = line.isEmpty ? basis : used + gap + basis;
    if (line.isNotEmpty && (button.style.wrapBefore || need > width + 0.5)) {
      lines.add(line);
      line = [];
      used = 0;
    }
    used = line.isEmpty ? basis : used + gap + basis;
    line.add((index, basis));
  }
  if (line.isNotEmpty) lines.add(line);
  return [
    for (final line in lines)
      () {
        final total =
            line.fold(0.0, (sum, slot) => sum + slot.$2) +
            gap * (line.length - 1);
        final free = width - total;
        double weight((int, double) slot) => free >= 0
            ? buttons[slot.$1].style.grow
            : buttons[slot.$1].style.shrink * slot.$2;
        final weights = line.fold(0.0, (sum, slot) => sum + weight(slot));
        return [
          for (final slot in line)
            (
              index: slot.$1,
              width: weights > 0
                  ? math.max(0.0, slot.$2 + free * weight(slot) / weights)
                  : slot.$2,
            ),
        ];
      }(),
  ];
}

/// 表單裡連續的一串按鈕：膠囊照書源寫的寬度排（[layoutSourceLoginButtons]）。
/// 有按鈕在執行時（[running]）那顆是選取的樣子，所有按鈕都不能按。
class SourceLoginButtons extends StatelessWidget
    implements GroupedSkeletonItem {
  const SourceLoginButtons({
    super.key,
    required this.buttons,
    required this.onPressed,
    this.running,
    this.enabled = true,
  });

  final List<SourceLoginRow> buttons;
  final ValueChanged<SourceLoginRow> onPressed;

  /// 正在執行的那顆。
  final SourceLoginRow? running;

  /// 為 false 時都不能按（例如正在登入）。
  final bool enabled;

  /// [GlassCapsule] 左右內距的合計。
  static const double _capsuleHorizontalPadding = (AppSpacing.md + 2) * 2;

  List<List<SourceLoginButtonSlot>> _lines(BuildContext context, double width) {
    final style = AppTextStyles.uiSm.copyWith(fontWeight: FontWeight.w500);
    return layoutSourceLoginButtons(
      buttons,
      width,
      // 照 [Text] 的方式量（疊上主題的預設字樣）：原本直接拿這個字樣量，少了
      // 主題的字型，膠囊窄了一點，字被截成「切換線…」。
      intrinsic: (button) =>
          GroupedItemShape.textSize(
            context,
            button.name.trim(),
            style: style,
            maxWidth: double.infinity,
            maxLines: 1,
          ).width.ceilToDouble() +
          _capsuleHorizontalPadding,
    );
  }

  /// 每顆膠囊一塊。
  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) {
    final inner = width - AppGrouped.margin * 2;
    final marks = <SkeletonShape>[];
    var y = 0.0;
    for (final line in _lines(context, inner)) {
      var x = AppGrouped.margin;
      for (final slot in line) {
        marks.add(
          SkeletonShape(
            Rect.fromLTWH(x, y, slot.width, GlassCapsule.height),
            radius: AppRadius.pillShape,
          ),
        );
        x += slot.width + kSourceLoginButtonGap;
      }
      y += GlassCapsule.height + kSourceLoginButtonGap;
    }
    return GroupedItemShape(
      math.max(0, y - kSourceLoginButtonGap),
      marks: marks,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppGrouped.margin),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final lines = _lines(context, constraints.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (lineIndex, line) in lines.indexed)
                Padding(
                  padding: EdgeInsets.only(
                    top: lineIndex == 0 ? 0 : kSourceLoginButtonGap,
                  ),
                  child: Row(
                    children: [
                      for (final (slotIndex, slot) in line.indexed) ...[
                        if (slotIndex > 0)
                          const SizedBox(width: kSourceLoginButtonGap),
                        SizedBox(
                          width: slot.width,
                          child: GlassCapsule(
                            label: buttons[slot.index].name.trim(),
                            blur: false,
                            tint: chrome.groupedSurface,
                            selected: identical(buttons[slot.index], running),
                            onTap: enabled && running == null
                                ? () => onPressed(buttons[slot.index])
                                : null,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 表單的一個輸入框：標題在上、輸入框在下。書源的欄位名常是一整句說明
/// （「搜索来源(多个来源用英文逗号分割)」），左右排放不下；填了字之後
/// 標題也要看得到，所以不當成提示字。
class SourceLoginField extends StatefulWidget implements GroupedSkeletonItem {
  const SourceLoginField({
    super.key,
    required this.row,
    required this.controller,
    this.enabled = true,
  });

  final SourceLoginRow row;
  final TextEditingController controller;
  final bool enabled;

  static final TextStyle _labelStyle = AppTextStyles.bodySm;

  static TextStyle _inputStyle(BuildContext context) => groupedInputStyle(
    context,
    AppTextStyles.bodyBase.copyWith(
      height: 1.3,
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );

  bool get _password => row.type == SourceLoginRowType.password;

  /// 標題的字，與輸入框裡的字（密碼照點的寬度）；密碼框右側的眼睛鈕把輸入框
  /// 撐到至少和它的點擊範圍一樣高，鈕上的圖示一塊。
  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) {
    final inner = width - AppGrouped.rowPadding * 2;
    final label = GroupedItemShape.text(
      context,
      row.name,
      style: _labelStyle,
      width: inner,
    );
    final text = controller.text;
    final suffixWidth = _password ? PasswordRevealButton.extent : 0.0;
    final field = groupedTextFieldShape(
      context,
      style: _inputStyle(context),
      width: inner - suffixWidth,
      text: _password ? '•' * text.length : text,
      maxLines: 1,
    );
    final fieldTop = AppSpacing.md + label.height;
    final box = math.max(field.height + AppSpacing.md * 2, suffixWidth);
    return GroupedItemShape(
      fieldTop + box,
      marks: [
        ...label.marksAt(const Offset(AppGrouped.rowPadding, AppSpacing.md)),
        ...field.marksAt(
          Offset(AppGrouped.rowPadding, fieldTop + AppSpacing.md),
        ),
        if (_password)
          ...groupedInputSuffixShape(
            context,
            PasswordRevealButton(revealed: false, onPressed: () {}),
            height: box,
          ).marksAt(
            Offset(AppGrouped.rowPadding + inner - suffixWidth, fieldTop),
          ),
      ],
    );
  }

  @override
  State<SourceLoginField> createState() => _SourceLoginFieldState();
}

class _SourceLoginFieldState extends State<SourceLoginField> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final password = widget._password;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppGrouped.rowPadding,
        AppSpacing.md,
        AppGrouped.rowPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.row.name,
            style: SourceLoginField._labelStyle.copyWith(
              color: chrome.sectionText,
            ),
          ),
          TextField(
            controller: widget.controller,
            enabled: widget.enabled,
            obscureText: password && !_revealed,
            maxLines: 1,
            autocorrect: false,
            enableSuggestions: !password,
            keyboardType: password
                ? TextInputType.visiblePassword
                : TextInputType.text,
            style: SourceLoginField._inputStyle(context),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                vertical: AppSpacing.md,
              ),
              suffixIcon: password
                  ? PasswordRevealButton(
                      revealed: _revealed,
                      onPressed: () => setState(() => _revealed = !_revealed),
                    )
                  : null,
              suffixIconConstraints: const BoxConstraints(
                minWidth: AppGrouped.rowMinHeight,
                minHeight: AppGrouped.rowMinHeight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
