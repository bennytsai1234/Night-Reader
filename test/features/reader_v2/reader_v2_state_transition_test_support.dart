import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/core/engine/reader/chinese_text_converter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/source_switch_service.dart';

class _UnusedBookSourceDao extends Fake implements BookSourceDao {}

/// Reusable page-layer fake for T5 and related state-transition tests.
///
/// The fake owns no network or database behavior. Each call can be delayed or
/// failed independently, while [resolution] supplies the deterministic
/// successful result used by the page orchestration.
class FakeReaderV2SourceSwitchService extends SourceSwitchService {
  FakeReaderV2SourceSwitchService({
    this.resolution,
    this.resolveError,
    this.persistError,
    this.resolveDelay = Duration.zero,
    this.persistDelay = Duration.zero,
    this.persistToDatabase = false,
  }) : super(sourceDao: _UnusedBookSourceDao());

  final PreparedSourceSwitch? resolution;
  final Object? resolveError;
  final Object? persistError;
  final Duration resolveDelay;
  final Duration persistDelay;
  final bool persistToDatabase;
  int prepareCalls = 0;
  int persistCalls = 0;
  Book? lastCurrentBook;
  Book? lastOldBook;
  PreparedSourceSwitch? lastPrepared;

  @override
  Future<PreparedSourceSwitch> prepareSwitch(
    Book currentBook,
    SearchBook candidate, {
    int? targetChapterIndex,
    String? targetChapterTitle,
  }) async {
    prepareCalls += 1;
    lastCurrentBook = currentBook.copyWith();
    if (resolveDelay != Duration.zero) await Future<void>.delayed(resolveDelay);
    final error = resolveError;
    if (error != null) throw error;
    final result = resolution;
    if (result == null) {
      throw StateError('FakeReaderV2SourceSwitchService has no resolution');
    }
    lastPrepared = result;
    return result;
  }

  @override
  Future<void> persistSwitch(
    Book oldBook,
    PreparedSourceSwitch resolution, {
    BookDao? bookDao,
    ChapterDao? chapterDao,
  }) async {
    persistCalls += 1;
    lastOldBook = oldBook.copyWith();
    lastPrepared = resolution;
    if (persistDelay != Duration.zero) await Future<void>.delayed(persistDelay);
    final error = persistError;
    if (error != null) throw error;
    if (persistToDatabase) {
      await super.persistSwitch(
        oldBook,
        resolution,
        bookDao: bookDao,
        chapterDao: chapterDao,
      );
    }
  }
}

/// The comparison contract used by the state-transition tests.
///
/// Presentation changes (T2/T3) require the anchor text to remain byte-for-
/// byte equal. Content conversion (T4) compares both probes after applying
/// the same conversion so a traditional/simplified spelling change is not
/// mistaken for a location change.
enum ReaderAnchorComparisonMode { exact, equivalentText }

/// A small semantic probe around a [ReaderV2Location].
///
/// The probe records the sentence containing the location rather than using
/// [ReaderV2Location.charOffset] as the assertion itself. This keeps the
/// assertion useful when a content conversion changes text length and the
/// corresponding offset is expected to move.
class ReaderAnchorProbe {
  const ReaderAnchorProbe({
    required this.chapterIndex,
    required this.charOffset,
    required this.anchorText,
  });

  factory ReaderAnchorProbe.capture({
    required ReaderV2Location location,
    required String sourceText,
  }) {
    final offset = location.charOffset.clamp(0, sourceText.length).toInt();
    final anchorText = _anchorSentenceAt(sourceText, offset);
    return ReaderAnchorProbe(
      chapterIndex: location.chapterIndex,
      charOffset: location.charOffset,
      anchorText: anchorText,
    );
  }

  final int chapterIndex;
  final int charOffset;
  final String anchorText;

  @override
  String toString() {
    return 'ReaderAnchorProbe(chapter=$chapterIndex, '
        'charOffset=$charOffset, anchorText=${anchorText.replaceAll('\n', r'\n')})';
  }
}

/// Thrown by [expectReaderAnchorPreserved] with both actual probes included.
class ReaderAnchorMismatch extends StateError {
  ReaderAnchorMismatch({
    required this.before,
    required this.after,
    required this.reason,
  }) : super(
         'Reader semantic anchor mismatch ($reason): '
         'before=$before; after=$after',
       );

  final ReaderAnchorProbe before;
  final ReaderAnchorProbe after;
  final String reason;
}

/// Assert semantic position preservation for a state transition.
///
/// [equivalentConversionType] is required for [equivalentText] and must be
/// `1` (canonical traditional) or `2` (canonical simplified). T4 can choose
/// either canonical direction; both sides are normalized to that same form.
void expectReaderAnchorPreserved(
  ReaderAnchorProbe before,
  ReaderAnchorProbe after, {
  ReaderAnchorComparisonMode mode = ReaderAnchorComparisonMode.exact,
  int? equivalentConversionType,
}) {
  if (before.chapterIndex != after.chapterIndex) {
    throw ReaderAnchorMismatch(
      before: before,
      after: after,
      reason: 'chapter changed',
    );
  }

  final beforeText = _normalizedAnchorText(
    before.anchorText,
    mode: mode,
    equivalentConversionType: equivalentConversionType,
  );
  final afterText = _normalizedAnchorText(
    after.anchorText,
    mode: mode,
    equivalentConversionType: equivalentConversionType,
  );
  if (beforeText != afterText) {
    throw ReaderAnchorMismatch(
      before: before,
      after: after,
      reason: 'anchor text changed: before="$beforeText", after="$afterText"',
    );
  }
}

/// Assert that a transition advanced the layout generation by [expectedDelta].
void expectReaderLayoutGenerationAdvanced(
  int before,
  int after, {
  int expectedDelta = 1,
}) {
  final expected = before + expectedDelta;
  if (after != expected) {
    throw StateError(
      'Reader layout generation mismatch: '
      'before=$before, after=$after, expected=$expected',
    );
  }
}

/// Assert the D9 contract shared by runtime and hybrid epoch namespaces.
void expectReaderEpochAlignedWithGeneration({
  required int epoch,
  required int layoutGeneration,
}) {
  if (epoch != layoutGeneration) {
    throw StateError(
      'Reader epoch is not aligned with layout generation: '
      'epoch=$epoch, layoutGeneration=$layoutGeneration',
    );
  }
}

/// Assert that every observed metrics entry belongs to the current signature.
///
/// An empty observation is rejected so a caller cannot accidentally turn a
/// cache test into a vacuous pass.
void expectReaderMetricsFreshForSignature({
  required int currentSignature,
  required Iterable<int> observedSignatures,
}) {
  final observed = observedSignatures.toList(growable: false);
  if (observed.isEmpty) {
    throw StateError('Reader metrics freshness observation is empty');
  }
  final stale = observed
      .where((signature) => signature != currentSignature)
      .toList(growable: false);
  if (stale.isNotEmpty) {
    throw StateError(
      'Reader metrics used stale layout signatures: '
      'current=$currentSignature, observed=$observed',
    );
  }
}

String _normalizedAnchorText(
  String text, {
  required ReaderAnchorComparisonMode mode,
  required int? equivalentConversionType,
}) {
  if (mode == ReaderAnchorComparisonMode.exact) return text;
  final conversionType = equivalentConversionType;
  if (conversionType != 1 && conversionType != 2) {
    throw ArgumentError.value(
      equivalentConversionType,
      'equivalentConversionType',
      'equivalentText requires conversion type 1 or 2',
    );
  }
  return const ChineseTextConverter().convert(
    text,
    convertType: conversionType!,
  );
}

String _anchorSentenceAt(String sourceText, int offset) {
  if (sourceText.isEmpty) return '';

  final safeOffset = offset.clamp(0, sourceText.length).toInt();
  const terminators = '。！？!?；;';
  var start = safeOffset;
  while (start > 0 && !terminators.contains(sourceText[start - 1])) {
    start -= 1;
  }
  var end = safeOffset;
  while (end < sourceText.length && !terminators.contains(sourceText[end])) {
    end += 1;
  }
  if (end < sourceText.length) end += 1;

  final sentence = sourceText.substring(start, end).trim();
  if (sentence.isNotEmpty) return sentence;

  // A paragraph without punctuation still provides a useful anchor.
  final paragraphStart = sourceText.lastIndexOf('\n', safeOffset - 1) + 1;
  final paragraphEnd = sourceText.indexOf('\n', safeOffset);
  return sourceText
      .substring(
        paragraphStart,
        paragraphEnd < 0 ? sourceText.length : paragraphEnd,
      )
      .trim();
}
