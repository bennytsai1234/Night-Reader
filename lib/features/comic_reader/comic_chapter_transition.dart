import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';

/// 換章分隔裡等著的那一話的狀態。
sealed class ComicTransitionStatus {
  const ComicTransitionStatus();
}

/// 兩邊都在條漫上，或沒有要等的那一話。
final class ComicTransitionIdle extends ComicTransitionStatus {
  const ComicTransitionIdle();
}

final class ComicTransitionLoading extends ComicTransitionStatus {
  const ComicTransitionLoading();
}

final class ComicTransitionFailed extends ComicTransitionStatus {
  const ComicTransitionFailed(this.message);
  final String message;
}

/// 換章分隔要寫的內容。
class ComicTransitionContent {
  const ComicTransitionContent({
    required this.fromTitle,
    required this.toTitle,
    this.gap = 0,
    this.status = const ComicTransitionIdle(),
  });

  /// 「已閱畢：」的章名；null 是第一話上面（「已達盡頭」）。
  final String? fromTitle;

  /// 「接下來：」的章名；null 是最後一話下面（「以下空白」）。
  final String? toTitle;

  /// 中間缺了幾話。
  final int gap;
  final ComicTransitionStatus status;
}

/// 夾在兩話之間的一塊，照 Mihon 的 `WebtoonTransitionHolder` 與
/// `ChapterTransition`：上下各留 128、左右 32，最寬 460；標題後接章名
/// （20、最多五行），兩段之間 24。第一話上面寫「已達盡頭」與「這一章：」，
/// 最後一話下面寫「以下空白」；中間缺章時多一張缺幾話的提醒；下一話還沒
/// 載好時在最下面顯示載入中或原因與「重試」。
///
/// 高度由 [extentOf] 照同樣的版面算出來，條漫在排版前就知道每一塊多高。
/// 失敗是要登入或驗證時，[remedyLabel] 與 [onRemedy] 另給一顆「登入」或
/// 「前往驗證」，排在「重試」前面。
class ComicChapterTransition extends StatelessWidget {
  const ComicChapterTransition({
    super.key,
    required this.content,
    required this.foreground,
    required this.accent,
    this.onRetry,
    this.remedyLabel,
    this.onRemedy,
  });

  final ComicTransitionContent content;
  final Color foreground;
  final Color accent;
  final VoidCallback? onRetry;

  /// 解決失敗的那一顆按鈕的字；沒有時是 null。
  final String? remedyLabel;
  final VoidCallback? onRemedy;

  static const double paddingVertical = 128;
  static const double paddingHorizontal = 32;
  static const double maxContentWidth = 460;
  static const double _labelGap = 4;
  static const double _sectionGap = 24;
  static const int _maxNameLines = 5;
  static const double _noticePaddingH = 16;
  static const double _noticePaddingV = 12;
  static const double _noticeIcon = 24;
  static const double _noticeIconGap = 16;
  static const double _progressSize = 24;
  static const double _retryHeight = 40;
  static const double _messageGap = 8;
  static const int _maxMessageLines = 3;

  static const TextStyle _labelStyle = AppTextStyles.titleMd;
  static const TextStyle _nameStyle = AppTextStyles.titleLg;
  static const TextStyle _noticeStyle = AppTextStyles.bodyBase;
  static const TextStyle _messageStyle = AppTextStyles.labelSm;

  static const String finishedLabel = '已閱畢：';
  static const String nextLabel = '接下來：';
  static const String currentLabel = '這一章：';
  static const String noPrevious = '已達盡頭';
  static const String noNext = '以下空白';

  static String gapNotice(int gap) => '中間缺了 $gap 話';

  /// 這一塊在 [width] 寬的條漫上多高。[base] 是條漫的預設字型樣式。
  static double extentOf(
    ComicTransitionContent content, {
    required double width,
    required TextScaler textScaler,
    required TextStyle base,
  }) {
    final contentWidth = _contentWidth(width);
    double text(String value, TextStyle style, {int? maxLines, double? w}) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: base.merge(style)),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: maxLines,
        ellipsis: maxLines == null ? null : '…',
      )..layout(maxWidth: w ?? contentWidth);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    double section(String label, String name) =>
        text(label, _labelStyle) +
        _labelGap +
        text(name, _nameStyle, maxLines: _maxNameLines);

    double notice(String value) {
      final textWidth =
          contentWidth - _noticePaddingH * 2 - _noticeIcon - _noticeIconGap;
      final body = text(value, _noticeStyle, w: textWidth);
      return (body > _noticeIcon ? body : _noticeIcon) + _noticePaddingV * 2;
    }

    var height = paddingVertical * 2;
    final from = content.fromTitle;
    final to = content.toTitle;
    height += from == null ? notice(noPrevious) : section(finishedLabel, from);
    if (to != null) {
      if (content.gap > 0) {
        height += _sectionGap + notice(gapNotice(content.gap));
      }
      height +=
          _sectionGap + section(from == null ? currentLabel : nextLabel, to);
    } else {
      height += _sectionGap + notice(noNext);
    }
    switch (content.status) {
      case ComicTransitionIdle():
        break;
      case ComicTransitionLoading():
        height += _sectionGap + _progressSize;
      case ComicTransitionFailed(:final message):
        height +=
            _sectionGap +
            text(message, _messageStyle, maxLines: _maxMessageLines) +
            _messageGap +
            _retryHeight;
    }
    return height;
  }

  static double _contentWidth(double width) {
    final available = width - paddingHorizontal * 2;
    final clamped = available < maxContentWidth ? available : maxContentWidth;
    return clamped < 1 ? 1 : clamped;
  }

  @override
  Widget build(BuildContext context) {
    final from = content.fromTitle;
    final to = content.toTitle;
    final children = <Widget>[
      if (from == null)
        _notice(Icons.info_outline_rounded, noPrevious, accent)
      else
        _section(finishedLabel, from),
      if (to != null) ...[
        if (content.gap > 0) ...[
          const SizedBox(height: _sectionGap),
          _notice(Icons.warning_amber_rounded, gapNotice(content.gap), accent),
        ],
        const SizedBox(height: _sectionGap),
        _section(from == null ? currentLabel : nextLabel, to),
      ] else ...[
        const SizedBox(height: _sectionGap),
        _notice(Icons.info_outline_rounded, noNext, accent),
      ],
      ..._status(),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: paddingHorizontal,
          vertical: paddingVertical,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: _contentWidth(constraints.maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String label, String name) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: _labelStyle.copyWith(color: foreground)),
      const SizedBox(height: _labelGap),
      Text(
        name,
        maxLines: _maxNameLines,
        overflow: TextOverflow.ellipsis,
        style: _nameStyle.copyWith(color: foreground),
      ),
    ],
  );

  Widget _notice(IconData icon, String text, Color iconColor) => Align(
    alignment: Alignment.center,
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: foreground.withValues(alpha: 0.24)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _noticePaddingH,
          vertical: _noticePaddingV,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: _noticeIcon, color: iconColor),
            const SizedBox(width: _noticeIconGap),
            Flexible(
              child: Text(
                text,
                style: _noticeStyle.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  List<Widget> _status() => switch (content.status) {
    ComicTransitionIdle() => const [],
    ComicTransitionLoading() => [
      const SizedBox(height: _sectionGap),
      Center(
        child: SizedBox.square(
          dimension: _progressSize,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: accent),
        ),
      ),
    ],
    ComicTransitionFailed(:final message) => [
      const SizedBox(height: _sectionGap),
      SizedBox(
        width: double.infinity,
        child: Text(
          message,
          maxLines: _maxMessageLines,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: _messageStyle.copyWith(
            color: foreground.withValues(alpha: 0.7),
          ),
        ),
      ),
      const SizedBox(height: _messageGap),
      Center(
        child: SizedBox(height: _retryHeight, child: _failedActions()),
      ),
    ],
  };

  Widget _failedActions() {
    final remedy = remedyLabel;
    final retry = TextButton(onPressed: onRetry, child: const Text('重試'));
    if (remedy == null) return retry;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(onPressed: onRemedy, child: Text(remedy)),
        const SizedBox(width: _messageGap),
        retry,
      ],
    );
  }
}
