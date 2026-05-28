import 'package:reader/core/models/replace_rule.dart';

class ReaderV2ProcessedChapter {
  const ReaderV2ProcessedChapter({
    required this.displayTitle,
    required this.content,
    this.effectiveReplaceRules = const <ReplaceRule>[],
    this.sameTitleRemoved = false,
  });

  final String displayTitle;
  final String content;
  final List<ReplaceRule> effectiveReplaceRules;
  final bool sameTitleRemoved;
}
