import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source_check/source_check_verdict.dart';

void main() {
  CheckIssue classify(
    Object error, {
    String stage = 'detail',
    CheckMode mode = CheckMode.search,
    bool networkDown = false,
  }) => issueFromException(
    stage: stage,
    error: error,
    mode: mode,
    networkDown: networkDown,
  );

  group('抓取出錯歸成哪種問題', () {
    test('網域查不到：網站失效；手機斷網時不算', () {
      final lookup = Exception('Failed host lookup: gone.example');
      final gone = classify(lookup);
      expect(gone.stage, 'upstream');
      expect(gone.health.label, siteBrokenSourceGroupTag);

      final offline = classify(lookup, networkDown: true);
      expect(offline.health.label, isNot(siteBrokenSourceGroupTag));
    });

    test('整段逾時：校驗超時，說明照逾時寫的', () {
      final issue = classify(TimeoutException('搜尋檢查超時：超過 20 秒'));
      expect(issue.stage, 'timeout');
      expect(issue.health.label, timeoutSourceGroupTag);
    });

    test('要登入：需要登入', () {
      final issue = classify(
        LoginCheckException('${LoginCheckException.marker}後閱讀'),
        stage: 'content',
      );
      expect(issue.health, loginRequiredSourceHealth);
    });

    test('搜尋到的書打不開會隔離書源，發現到的只標發現失效', () {
      final error = Exception('解析失敗');
      for (final (stage, label) in [
        ('detail', detailBrokenSourceGroupTag),
        ('toc', tocBrokenSourceGroupTag),
        ('content', contentBrokenSourceGroupTag),
      ]) {
        final searched = classify(error, stage: stage);
        expect(searched.health.label, label);
        expect(searched.health.quarantined, isTrue, reason: stage);
      }
      for (final (stage, label) in [
        ('discovery:detail', discoveryDetailBrokenSourceGroupTag),
        ('discovery:toc', discoveryTocBrokenSourceGroupTag),
        ('discovery:content', discoveryContentBrokenSourceGroupTag),
        ('discovery', discoveryBrokenSourceGroupTag),
      ]) {
        final discovered = classify(
          error,
          stage: stage,
          mode: CheckMode.discovery,
        );
        expect(discovered.health.label, label);
        expect(discovered.health.quarantined, isFalse, reason: stage);
        expect(discovered.health.allowsSearch, isTrue, reason: stage);
      }
    });

    test('搜尋本身出錯：搜尋失效，閱讀照常', () {
      final issue = classify(Exception('解析失敗'), stage: 'search');
      expect(issue.health.label, searchBrokenSourceGroupTag);
      expect(issue.health.allowsReading, isTrue);
    });
  });

  group('幾個問題合成一個結論', () {
    CheckIssue issue(String stage, String message, SourceRuntimeHealth h) =>
        CheckIssue(stage: stage, message: message, health: h);

    test('照優先順序挑主要的：要登入比正文失效優先', () {
      final content = issue(
        'content',
        '過短',
        contentHealthFor(CheckMode.search),
      );
      final login = issue('content', '要登入', loginRequiredSourceHealth);
      expect(primaryIssue([content, login]), same(login));
      expect(primaryIssue([login, content]), same(login));
    });

    test('說明照階段串起來，同一段同一句只寫一次', () {
      final a = issue('search', '搜尋結果為空', searchRuleBrokenHealth);
      final b = issue('detail', '詳情頁返回空資料', detailHealthFor(CheckMode.search));
      expect(composeIssueMessage([a, b, a]), '搜尋: 搜尋結果為空；詳情: 詳情頁返回空資料');
    });

    test('會隔離或該清理的問題之後不再測發現', () {
      expect(
        hasTerminalIssue([
          issue('search', '空', searchRuleBrokenHealth),
          issue('discovery', '空', discoveryBrokenHealth),
        ]),
        isFalse,
      );
      expect(
        hasTerminalIssue([issue('toc', '下載站', downloadOnlyHealth)]),
        isTrue,
      );
    });
  });
}
