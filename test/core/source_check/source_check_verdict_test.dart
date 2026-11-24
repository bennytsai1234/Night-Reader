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

    test('整段逾時：校驗超時，說明一律是同一句', () {
      final issue = classify(TimeoutException('搜尋檢查超時：超過 20 秒'));
      expect(issue.stage, 'timeout');
      expect(issue.message, '校驗超時或來源響應過慢');
      expect(issue.health.label, timeoutSourceGroupTag);
    });

    test('要登入：需要登入', () {
      final issue = classify(
        LoginCheckException('${LoginCheckException.marker}後閱讀'),
        stage: 'content',
      );
      expect(issue.health, loginRequiredSourceHealth);
    });

    test('規則或網址帶 vip 字樣的出錯不算要登入', () {
      // 解析錯誤的字串帶著規則與網址；網站叫 vipxs、規則提到 vip 時，一般的
      // 規則出錯被判成「需要登入」，書源留在搜尋裡、也不交給 AI 修。
      final parsing = classify(
        ParsingException(
          'TypeError',
          rule: 'class.vip-list@text',
          url: 'https://www.vipxs.la/book/1',
        ),
      );
      expect(parsing.health.label, detailBrokenSourceGroupTag);

      // 連不上：錯誤字串帶著主機名稱。
      final refused = classify(
        Exception('Connection refused, address = www.vipxs.la'),
        stage: 'content',
      );
      expect(refused.health, isNot(loginRequiredSourceHealth));
    });

    test('規則 JS 包住的登入牆照樣算要登入', () {
      // 字串規則的 JS 出錯時包成「解析字串失敗」，登入的訊息在包住的那一層。
      final wrapped = classify(
        ParsingException(
          '解析字串失敗',
          rule: '@js:java.ajax(url)',
          url: 'https://example.com/c/1',
          originalError: RuleJsException(
            'Error: 正文${LoginCheckException.marker}後閱讀',
          ),
        ),
        stage: 'content',
      );
      expect(wrapped.health, loginRequiredSourceHealth);

      final wall = classify(
        ParsingException(
          '解析字串失敗',
          originalError: LoginCheckException(
            '正文${LoginCheckException.marker}後閱讀',
          ),
        ),
        stage: 'content',
      );
      expect(wall.health, loginRequiredSourceHealth);
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

    test('搜尋到的書正文：抓取出錯和抓到過短的說明不同', () {
      expect(
        classify(Exception('解析失敗'), stage: 'content').health.description,
        '正文抓取失敗或無法閱讀',
      );
      expect(contentHealthFor(CheckMode.search).description, '正文內容過短或為空');
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
        reason: '該清理',
      );
      expect(
        hasTerminalIssue([
          issue('detail', '詳情頁返回空資料', detailHealthFor(CheckMode.search)),
        ]),
        isTrue,
        reason: '會隔離',
      );
    });
  });
}
