import 'package:night_reader/core/models/replace_rule.dart';

/// BookContent - 處理後的正文內容 (對標 Android help/book/BookContent.kt)
class BookContent {
  final String content;
  final List<ReplaceRule> effectiveReplaceRules;
  final bool sameTitleRemoved;

  BookContent({
    required this.content,
    this.effectiveReplaceRules = const [],
    this.sameTitleRemoved = false,
  });
}
