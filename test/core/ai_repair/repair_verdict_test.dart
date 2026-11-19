import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_repair_prompt.dart';
import 'package:night_reader/core/ai_repair/repair_verdict.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source_check/source_check_isolate.dart';

/// 搜尋與發現各有書單規則；[ownExplore] 是 false 時發現借用搜尋的規則。
BookSource _source({String search = 'class.book', bool ownExplore = true}) =>
    BookSource(
      bookSourceUrl: 'https://site.example',
      bookSourceName: 'site',
      searchUrl: '/s?q={{key}}',
      exploreUrl: '/explore',
      ruleSearch: SearchRule(bookList: search, name: 'a@text'),
      ruleExplore: ownExplore
          ? ExploreRule(bookList: 'class.hot', name: 'a@text')
          : null,
    );

SourceRuntimeHealth _health(SourceHealthCategory category) =>
    SourceRuntimeHealth(
      category: category,
      label: '發現失效',
      description: '',
      allowsSearch: true,
      allowsReading: true,
      cleanupCandidate: false,
      quarantined: false,
    );

/// 校驗結果：[broken] 是 null 時沒有問題。
SourceCheckIsolateResult _result(
  BookSource source, {
  SourceHealthCategory? broken,
}) => SourceCheckIsolateResult(
  stage: broken == null ? 'done' : 'explore',
  message: broken == null ? '校驗成功' : '發現為空',
  isHealthy: broken == null,
  updatedSourceJson:
      (BookSource.fromJson(source.toJson())..addHealthGroups(
            broken == null ? SourceRuntimeHealth.healthy : _health(broken),
          ))
          .toJson(),
  logs: const [],
  diagnostics: const [],
);

void main() {
  group('usableFix', () {
    final original = _source(search: 'class.old');
    final candidate = _source();

    test('a timed-out check is not a fix; a healthy one is', () {
      expect(
        usableFix(
          null,
          original,
          candidate,
          before: SourceHealthCategory.contentBroken,
        ),
        isFalse,
      );
      expect(
        usableFix(
          _result(candidate),
          original,
          candidate,
          before: SourceHealthCategory.contentBroken,
        ),
        isTrue,
      );
    });

    test('only discovery still failing counts when reading was broken and the '
        'AI left discovery alone', () {
      final result = _result(
        candidate,
        broken: SourceHealthCategory.discoveryBroken,
      );
      expect(
        usableFix(
          result,
          original,
          candidate,
          before: SourceHealthCategory.contentBroken,
        ),
        isTrue,
      );
      // 原本就只壞發現頁、或不知道原本壞在哪：要整個沒問題。
      expect(
        usableFix(
          result,
          original,
          candidate,
          before: SourceHealthCategory.discoveryBroken,
        ),
        isFalse,
      );
      expect(usableFix(result, original, candidate, before: null), isFalse);
    });

    test('a search change that discovery borrows is not a fix while discovery '
        'fails', () {
      final borrowing = _source(search: 'class.old', ownExplore: false);
      final changed = _source(ownExplore: false);
      expect(
        usableFix(
          _result(changed, broken: SourceHealthCategory.discoveryBroken),
          borrowing,
          changed,
          before: SourceHealthCategory.contentBroken,
        ),
        isFalse,
      );
    });

    test('a change to the discovery rules is not a fix while discovery '
        'fails', () {
      final changed = _source()..ruleExplore!.name = 'b@text';
      expect(
        usableFix(
          _result(changed, broken: SourceHealthCategory.discoveryBroken),
          _source(),
          changed,
          before: SourceHealthCategory.contentBroken,
        ),
        isFalse,
      );
    });

    test('reading still broken is not a fix, even with discovery left '
        'alone', () {
      expect(
        usableFix(
          _result(candidate, broken: SourceHealthCategory.contentBroken),
          original,
          candidate,
          before: SourceHealthCategory.contentBroken,
        ),
        isFalse,
      );
    });
  });

  test('discoveryNote tells the AI only when discovery borrows the changed '
      'search rules', () {
    final borrowing = _source(search: 'class.old', ownExplore: false);
    final changed = _source(ownExplore: false);
    final discoveryFails = _result(
      changed,
      broken: SourceHealthCategory.discoveryBroken,
    );
    expect(
      discoveryNote(discoveryFails, borrowing, changed),
      aiRepairExploreBorrowsSearch,
    );
    expect(discoveryNote(_result(changed), borrowing, changed), isNull);
    expect(discoveryNote(null, borrowing, changed), isNull);
    expect(
      discoveryNote(
        _result(changed, broken: SourceHealthCategory.contentBroken),
        borrowing,
        changed,
      ),
      isNull,
    );
    expect(
      discoveryNote(
        _result(_source(), broken: SourceHealthCategory.discoveryBroken),
        _source(search: 'class.old'),
        _source(),
      ),
      isNull,
    );
  });

  test('candidateOrNull is null for a field it cannot hold', () {
    final original = _source();
    expect(
      candidateOrNull(original, sourceForAi(original))?.bookSourceUrl,
      original.bookSourceUrl,
    );
    expect(
      candidateOrNull(original, {
        ...sourceForAi(original),
        'bookSourceType': double.infinity,
      }),
      isNull,
    );
  });
}
