import 'package:flutter/material.dart';
import '../theme/app_chrome.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';
import 'glass.dart';

/// [FolderTabs] 的單一分頁。
@immutable
class FolderTab<T> {
  const FolderTab(this.value, this.label);

  final T value;
  final String label;
}

/// Telegram 資料夾式橫向分頁：玻璃膠囊軌道上滑動的選取膠囊。
///
/// 分頁放得下時等分寬度；放不下時可橫向捲動，切換後把選取項捲到可視範圍
/// 中央。為受控元件：點擊已選取的分頁不會回報。
class FolderTabs<T> extends StatefulWidget {
  const FolderTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
  });

  /// 軌道高度（Telegram 40pt 膠囊）。
  static const double height = 40.0;

  final List<FolderTab<T>> tabs;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  State<FolderTabs<T>> createState() => _FolderTabsState<T>();
}

class _FolderTabsState<T> extends State<FolderTabs<T>> {
  /// 軌道內縮與分頁左右內距（Telegram 3pt／16pt）。
  static const double _inset = 3.0;
  static const double _itemPadding = 16.0;

  final ScrollController _scrollController = ScrollController();
  int? _revealedIndex;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  TextStyle _labelStyle(bool selected) => AppTextStyles.uiMd.copyWith(
    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
  );

  List<double> _measureWidths(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return [
      for (final tab in widget.tabs)
        () {
          // 以選取時的字重量測，切換時寬度不跳動。
          final painter = TextPainter(
            text: TextSpan(text: tab.label, style: _labelStyle(true)),
            textDirection: direction,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final width = painter.width.ceilToDouble() + _itemPadding * 2;
          painter.dispose();
          return width;
        }(),
    ];
  }

  void _revealSelected(int index, List<double> offsets, List<double> widths) {
    if (_revealedIndex == index) return;
    final first = _revealedIndex == null;
    _revealedIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final target = (offsets[index] -
              (position.viewportDimension - widths[index]) / 2)
          .clamp(0.0, position.maxScrollExtent);
      if (first) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: AppMotion.spring,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    final selectedIndex = widget.tabs.indexWhere(
      (tab) => tab.value == widget.selected,
    );

    return SizedBox(
      height: FolderTabs.height,
      child: GlassSurface(
        borderRadius: AppRadius.pillShape,
        shadow: false,
        child: Padding(
          padding: const EdgeInsets.all(_inset),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final available = constraints.maxWidth;
              var widths = _measureWidths(context);
              final total = widths.fold<double>(0, (sum, w) => sum + w);
              final fits = total <= available;
              if (fits && widths.isNotEmpty) {
                final widest = widths.reduce((a, b) => a > b ? a : b);
                final even = available / widths.length;
                // 每個分頁都放得進等分寬度時等分；否則依標籤長度按比例撐滿。
                widths =
                    widest <= even
                        ? List.filled(widths.length, even)
                        : [for (final w in widths) w * available / total];
              }
              final offsets = <double>[];
              var cursor = 0.0;
              for (final width in widths) {
                offsets.add(cursor);
                cursor += width;
              }
              if (selectedIndex >= 0 && !fits) {
                _revealSelected(selectedIndex, offsets, widths);
              }

              return SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics:
                    fits
                        ? const NeverScrollableScrollPhysics()
                        : const BouncingScrollPhysics(),
                child: SizedBox(
                  width: fits ? available : total,
                  height: constraints.maxHeight,
                  child: Stack(
                    children: [
                      if (selectedIndex >= 0)
                        AnimatedPositioned(
                          duration: AppMotion.spring,
                          curve: AppMotion.springCurve,
                          left: offsets[selectedIndex],
                          width: widths[selectedIndex],
                          top: 0,
                          bottom: 0,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: chrome.selectionLens,
                              borderRadius: AppRadius.pillShape,
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          for (var i = 0; i < widget.tabs.length; i++)
                            SizedBox(
                              width: widths[i],
                              child: Semantics(
                                button: true,
                                selected: i == selectedIndex,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap:
                                      i == selectedIndex
                                          ? null
                                          : () => widget.onChanged(
                                            widget.tabs[i].value,
                                          ),
                                  child: Center(
                                    child: AnimatedDefaultTextStyle(
                                      duration: AppMotion.fade,
                                      curve: AppMotion.fadeCurve,
                                      style: _labelStyle(
                                        i == selectedIndex,
                                      ).copyWith(
                                        color:
                                            i == selectedIndex
                                                ? scheme.primary
                                                : scheme.onSurface,
                                      ),
                                      child: Text(
                                        widget.tabs[i].label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
