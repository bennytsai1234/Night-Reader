import 'package:flutter/foundation.dart';
import 'package:night_reader/core/constant/app_pattern.dart';
import 'package:night_reader/core/engine/reader/chinese_text_converter.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/replace_rule.dart';

import 'reader_v2_processed_chapter.dart';

class ReaderV2ContentTransformer {
  const ReaderV2ContentTransformer();

  Future<ReaderV2ProcessedChapter> process({
    required Book book,
    required BookChapter chapter,
    required String rawContent,
    required List<ReplaceRule> enabledRules,
    required int chineseConvertType,
  }) async {
    final converter = const ChineseTextConverter();
    final result = await compute(_processInBackground, <String, Object?>{
      'bookName': book.name,
      'bookOrigin': book.origin,
      'chapterTitle': chapter.title,
      'rawContent': rawContent,
      'rulesJson': enabledRules.map((rule) => rule.toJson()).toList(),
      'useReplaceRules': book.getUseReplaceRule(),
      'reSegmentEnabled': book.getReSegment(),
    });
    final effectiveRules = (result['effectiveRules'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(ReplaceRule.fromJson)
        .toList(growable: false);
    return ReaderV2ProcessedChapter(
      displayTitle: converter.convert(
        result['displayTitle'] as String? ?? '',
        convertType: chineseConvertType,
      ),
      content: converter.convert(
        result['content'] as String? ?? '',
        convertType: chineseConvertType,
      ),
      effectiveReplaceRules: effectiveRules,
      sameTitleRemoved: result['sameTitleRemoved'] as bool? ?? false,
    );
  }

  static Map<String, Object?> _processInBackground(Map<String, Object?> args) {
    final bookName = args['bookName'] as String? ?? '';
    final bookOrigin = args['bookOrigin'] as String? ?? '';
    final chapterTitle = args['chapterTitle'] as String? ?? '';
    final rawContent = args['rawContent'] as String? ?? '';
    final rulesJson =
        (args['rulesJson'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
    final useReplaceRules = args['useReplaceRules'] as bool? ?? true;
    final reSegmentEnabled = args['reSegmentEnabled'] as bool? ?? true;
    final rules =
        rulesJson
            .map(ReplaceRule.fromJson)
            .where((rule) => rule.isEnabled)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));

    final titleRules = rules
        .where(
          (rule) =>
              rule.appliesToTitle(bookName: bookName, bookOrigin: bookOrigin),
        )
        .toList(growable: false);
    final contentResult = _processContent(
      bookName: bookName,
      bookOrigin: bookOrigin,
      chapterTitle: chapterTitle,
      rawContent: rawContent,
      rules: rules,
      titleRules: titleRules,
      useReplaceRules: useReplaceRules,
      reSegmentEnabled: reSegmentEnabled,
    );
    final displayTitle = _processTitle(
      chapterTitle: chapterTitle,
      rules: titleRules,
      useReplaceRules: useReplaceRules,
    );

    return <String, Object?>{
      'displayTitle': displayTitle,
      'content': contentResult.content,
      'effectiveRules': contentResult.effectiveReplaceRules
          .map((rule) => rule.toJson())
          .toList(growable: false),
      'sameTitleRemoved': contentResult.sameTitleRemoved,
    };
  }

  static ReaderV2ProcessedChapter _processContent({
    required String bookName,
    required String bookOrigin,
    required String chapterTitle,
    required String rawContent,
    required List<ReplaceRule> rules,
    required List<ReplaceRule> titleRules,
    required bool useReplaceRules,
    required bool reSegmentEnabled,
  }) {
    if (rawContent.isEmpty) {
      return const ReaderV2ProcessedChapter(displayTitle: '', content: '');
    }

    var content = rawContent;
    var sameTitleRemoved = false;
    final effectiveRules = <ReplaceRule>[];

    final nameRegex = RegExp.escape(bookName);
    final titleRegex = RegExp.escape(
      chapterTitle,
    ).replaceAll(AppPattern.spaceRegex, r'\s*');
    final duplicateTitlePattern = RegExp(
      '^(\\s|\\p{P}|$nameRegex)*$titleRegex(\\s)*',
      unicode: true,
    );
    final duplicateTitleMatch = duplicateTitlePattern.firstMatch(content);
    if (duplicateTitleMatch != null) {
      content = content.substring(duplicateTitleMatch.end);
      sameTitleRemoved = true;
    } else if (useReplaceRules && titleRules.isNotEmpty) {
      final displayTitle = _processTitle(
        chapterTitle: chapterTitle,
        rules: titleRules,
        useReplaceRules: true,
      );
      if (displayTitle.trim().isNotEmpty && displayTitle != chapterTitle) {
        final displayTitleRegex = RegExp.escape(
          displayTitle,
        ).replaceAll(AppPattern.spaceRegex, r'\s*');
        final displayDuplicateTitlePattern = RegExp(
          '^(\\s|\\p{P}|$nameRegex)*$displayTitleRegex(\\s)*',
          unicode: true,
        );
        final displayDuplicateTitleMatch = displayDuplicateTitlePattern
            .firstMatch(content);
        if (displayDuplicateTitleMatch != null) {
          content = content.substring(displayDuplicateTitleMatch.end);
          sameTitleRemoved = true;
        }
      }
    }

    if (reSegmentEnabled) {
      content = _reSegment(content);
    }

    if (useReplaceRules) {
      content = content.split('\n').map((line) => line.trim()).join('\n');
      for (final rule in rules) {
        if (!rule.appliesToContent(
          bookName: bookName,
          bookOrigin: bookOrigin,
        )) {
          continue;
        }

        try {
          final previous = content;
          content = rule.apply(content);
          if (content != previous) {
            effectiveRules.add(rule);
          }
        } catch (_) {}
      }
    }

    final paragraphs = <String>[];
    const indent = '　　';
    for (final line in content.split('\n')) {
      final paragraph = line.trim().replaceAll('\u00A0', ' ');
      if (paragraph.isNotEmpty) {
        paragraphs.add('$indent$paragraph');
      }
    }

    return ReaderV2ProcessedChapter(
      displayTitle: '',
      content: paragraphs.join('\n'),
      effectiveReplaceRules: List<ReplaceRule>.unmodifiable(effectiveRules),
      sameTitleRemoved: sameTitleRemoved,
    );
  }

  static String _reSegment(String content) {
    final normalized = content
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n');
    final nonEmptyLines =
        normalized.split('\n').where((line) => line.trim().isNotEmpty).length;
    if (nonEmptyLines > 1 || normalized.trim().length < 180) {
      return normalized;
    }
    return _splitSingleLineByPunctuation(normalized);
  }

  static String _splitSingleLineByPunctuation(String content) {
    final buffer = StringBuffer();
    for (var index = 0; index < content.length; index++) {
      final char = content[index];
      buffer.write(char);
      if (!_sentenceEndChars.contains(char)) continue;

      while (index + 1 < content.length &&
          _sentenceCloseChars.contains(content[index + 1])) {
        index += 1;
        buffer.write(content[index]);
      }

      if (index + 1 < content.length && content[index + 1].trim().isNotEmpty) {
        buffer.write('\n');
      }
    }
    return buffer.toString();
  }

  static const String _sentenceEndChars = '。！？!?；;';
  static const String _sentenceCloseChars = '」』”’））》〉】]';

  static String _processTitle({
    required String chapterTitle,
    required List<ReplaceRule> rules,
    required bool useReplaceRules,
  }) {
    var displayTitle = chapterTitle.replaceAll(RegExp(r'[\r\n]'), '');
    if (useReplaceRules) {
      for (final rule in rules) {
        if (rule.pattern.isEmpty) continue;
        try {
          final next = rule.apply(displayTitle);
          if (next.trim().isNotEmpty) {
            displayTitle = next;
          }
        } catch (_) {}
      }
    }
    return displayTitle;
  }
}
