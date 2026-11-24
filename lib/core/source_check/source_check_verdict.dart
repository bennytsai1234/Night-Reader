// 書源校驗的判定：抓取出錯時歸成哪個健康分組、問題的優先順序與合併成一句
// 結論、階段的中文名稱。不讀校驗的狀態，給什麼就照什麼判。
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/network/cloudflare.dart';
import 'package:night_reader/core/network/error_text.dart';
import 'package:night_reader/core/network/str_response.dart';
import 'package:night_reader/core/source/source_interaction.dart';

/// 這一段校驗從哪裡拿到書：搜尋或發現。
enum CheckMode {
  search,
  discovery;

  String get label => this == CheckMode.search ? '搜尋' : '發現';
}

/// 校驗找到的一個問題：在哪一段、說明，和它讓書源變成哪種健康狀態。
class CheckIssue {
  final String stage;
  final String message;
  final SourceRuntimeHealth health;

  const CheckIssue({
    required this.stage,
    required this.message,
    required this.health,
  });
}

String checkStage(CheckMode mode, String detailStage) =>
    mode == CheckMode.search ? detailStage : 'discovery:$detailStage';

/// 抓取出錯、又不是網站、登入、驗證或逾時的問題時，照出錯的那一段
/// （[stage]）算哪一種失效。搜尋到的書打不開會隔離書源；發現到的書打不開
/// 只標發現失效，搜尋與閱讀照常。
SourceRuntimeHealth _brokenHealthFor(CheckMode mode, String stage) {
  if (mode == CheckMode.discovery) {
    if (stage.endsWith('detail')) return _discoveryDetailBrokenHealth;
    if (stage.endsWith('toc')) return _discoveryTocBrokenHealth;
    if (stage.endsWith('content')) return _discoveryContentBrokenHealth;
    return discoveryBrokenHealth;
  }
  if (stage == 'search') return searchRuleBrokenHealth;
  if (stage.endsWith('detail')) return _detailBrokenHealth;
  if (stage.endsWith('toc')) return _tocBrokenHealth;
  return _contentFetchFailedHealth;
}

SourceRuntimeHealth detailHealthFor(CheckMode mode) => mode == CheckMode.search
    ? _detailBrokenHealth
    : _discoveryDetailBrokenHealth;

SourceRuntimeHealth tocHealthFor(CheckMode mode) =>
    mode == CheckMode.search ? _tocBrokenHealth : _discoveryTocBrokenHealth;

/// 正文抓得到、內容卻過短或是空的（抓取出錯是 [_contentFetchFailedHealth]）。
SourceRuntimeHealth contentHealthFor(CheckMode mode) => mode == CheckMode.search
    ? _contentTooShortHealth
    : _discoveryContentBrokenHealth;

const searchRuleBrokenHealth = SourceRuntimeHealth(
  category: SourceHealthCategory.searchBroken,
  label: searchBrokenSourceGroupTag,
  description: '搜尋規則已失效',
  allowsSearch: false,
  allowsReading: true,
  cleanupCandidate: false,
  quarantined: false,
);

const discoveryBrokenHealth = SourceRuntimeHealth(
  category: SourceHealthCategory.discoveryBroken,
  label: discoveryBrokenSourceGroupTag,
  description: '發現規則已失效',
  allowsSearch: true,
  allowsReading: true,
  cleanupCandidate: false,
  quarantined: false,
);

const _discoveryDetailBrokenHealth = SourceRuntimeHealth(
  category: SourceHealthCategory.discoveryDetailBroken,
  label: discoveryDetailBrokenSourceGroupTag,
  description: '發現書籍詳情失效',
  allowsSearch: true,
  allowsReading: true,
  cleanupCandidate: false,
  quarantined: false,
);

const _discoveryTocBrokenHealth = SourceRuntimeHealth(
  category: SourceHealthCategory.discoveryTocBroken,
  label: discoveryTocBrokenSourceGroupTag,
  description: '發現書籍目錄失效',
  allowsSearch: true,
  allowsReading: true,
  cleanupCandidate: false,
  quarantined: false,
);

const _discoveryContentBrokenHealth = SourceRuntimeHealth(
  category: SourceHealthCategory.discoveryContentBroken,
  label: discoveryContentBrokenSourceGroupTag,
  description: '發現書籍正文失效',
  allowsSearch: true,
  allowsReading: true,
  cleanupCandidate: false,
  quarantined: false,
);

const _detailBrokenHealth = SourceRuntimeHealth(
  category: SourceHealthCategory.detailBroken,
  label: detailBrokenSourceGroupTag,
  description: '詳情頁無法正常解析',
  allowsSearch: false,
  allowsReading: false,
  cleanupCandidate: false,
  quarantined: true,
);

const _tocBrokenHealth = SourceRuntimeHealth(
  category: SourceHealthCategory.tocBroken,
  label: tocBrokenSourceGroupTag,
  description: '目錄抓取失敗或沒有可閱讀章節',
  allowsSearch: false,
  allowsReading: false,
  cleanupCandidate: false,
  quarantined: true,
);

const _contentFetchFailedHealth = SourceRuntimeHealth(
  category: SourceHealthCategory.contentBroken,
  label: contentBrokenSourceGroupTag,
  description: '正文抓取失敗或無法閱讀',
  allowsSearch: false,
  allowsReading: false,
  cleanupCandidate: false,
  quarantined: true,
);

const _contentTooShortHealth = SourceRuntimeHealth(
  category: SourceHealthCategory.contentBroken,
  label: contentBrokenSourceGroupTag,
  description: '正文內容過短或為空',
  allowsSearch: false,
  allowsReading: false,
  cleanupCandidate: false,
  quarantined: true,
);

const downloadOnlyHealth = SourceRuntimeHealth(
  category: SourceHealthCategory.downloadOnly,
  label: downloadOnlySourceGroupTag,
  description: '來源只提供下載，不提供線上正文閱讀',
  allowsSearch: false,
  allowsReading: false,
  cleanupCandidate: true,
  quarantined: false,
);

CheckIssue paidChapterIssue(CheckMode mode, BookChapter chapter) {
  final title = compactChapterTitle(chapter.title);
  return CheckIssue(
    stage: checkStage(mode, 'toc'),
    message: title.isEmpty ? '目錄有付費章節' : '目錄有付費章節: $title',
    health: paidSourceHealth,
  );
}

CheckIssue lockedChapterIssue(CheckMode mode, BookChapter chapter) {
  final title = compactChapterTitle(chapter.title);
  return CheckIssue(
    stage: checkStage(mode, 'content'),
    message: title.isEmpty ? '章節都是付費章節' : '章節都是付費章節: $title',
    health: loginRequiredSourceHealth,
  );
}

/// 這本書的詳情、目錄或正文打不開（會讓書源被隔離的那幾種）。
bool bookCannotOpen(CheckIssue issue) => const {
  SourceHealthCategory.detailBroken,
  SourceHealthCategory.tocBroken,
  SourceHealthCategory.contentBroken,
}.contains(issue.health.category);

/// 網域查不到（DNS 沒有這個名字）：Dart 的訊息一律是 `Failed host lookup`。
bool hostNotFound(Object error) =>
    error.toString().contains('Failed host lookup');

bool _looksLikeTimeout(String normalized) =>
    normalized.contains('timeout') ||
    normalized.contains('timed out') ||
    normalized.contains('future not completed');

bool _looksLikeBlockedUpstream(String normalized) =>
    normalized.contains(' 401') ||
    normalized.contains(' 403') ||
    normalized.contains(' 404') ||
    normalized.contains(' 429') ||
    normalized.contains(' 502') ||
    normalized.contains(' 503') ||
    normalized.contains('forbidden') ||
    normalized.contains('cloudflare') ||
    // 連不上（連線被拒、加密連線失敗）：網站那邊的問題，不是太慢。書源的
    // 連線不驗憑證（sourceHttpClient），憑證有問題不會走到這裡。
    normalized.contains('socketexception') ||
    normalized.contains('handshakeexception');

int _issuePriority(SourceHealthCategory category) {
  switch (category) {
    case SourceHealthCategory.nonNovel:
      return 100;
    case SourceHealthCategory.loginRequired:
      return 95;
    case SourceHealthCategory.verificationRequired:
      return 94;
    case SourceHealthCategory.downloadOnly:
      return 90;
    case SourceHealthCategory.paid:
      return 89;
    case SourceHealthCategory.contentBroken:
      return 80;
    case SourceHealthCategory.tocBroken:
      return 70;
    case SourceHealthCategory.detailBroken:
      return 60;
    case SourceHealthCategory.searchBroken:
      return 50;
    case SourceHealthCategory.upstreamUnstable:
      return 40;
    case SourceHealthCategory.discoveryDetailBroken:
      return 29;
    case SourceHealthCategory.discoveryTocBroken:
      return 28;
    case SourceHealthCategory.discoveryContentBroken:
      return 27;
    case SourceHealthCategory.discoveryBroken:
      return 26;
    case SourceHealthCategory.healthy:
      return 0;
  }
}

String checkStageLabel(String stage) {
  switch (stage) {
    case 'search':
      return '搜尋';
    case 'discovery':
      return '發現';
    case 'detail':
      return '詳情';
    case 'toc':
      return '目錄';
    case 'content':
      return '正文';
    case 'discovery:detail':
      return '發現詳情';
    case 'discovery:toc':
      return '發現目錄';
    case 'discovery:content':
      return '發現正文';
    case 'filter':
      return '預檢';
    case 'timeout':
      return '超時';
    case 'upstream':
      return '上游';
    default:
      return stage;
  }
}

/// 網站擋下了夜讀（`CloudflareInterceptor` 判斷的那幾種）。先看錯誤本身的
/// 種類；包進解析錯誤後只剩文字時，比對它們的訊息。
bool blockedBySite(Object error, String normalized) {
  final inner = error is DioException ? error.error : error;
  if (inner is HumanVerificationRequiredException ||
      inner is SiteBlockedException ||
      inner is ChallengeNotPassedException) {
    return true;
  }
  return [
    HumanVerificationRequiredException().message,
    SiteBlockedException().message,
    ChallengeNotPassedException().message,
  ].any(normalized.contains);
}

String compactCheckMessage(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '未知錯誤';
  final firstLine = trimmed.split('\n').first.trim();
  return firstLine.length > 220
      ? '${firstLine.substring(0, 220)}...'
      : firstLine;
}

String compactChapterTitle(String title) {
  final trimmed = title.trim();
  if (trimmed.length <= 40) return trimmed;
  return '${trimmed.substring(0, 40)}...';
}

CheckIssue issueFromException({
  required String stage,
  required Object error,
  required CheckMode mode,
  required bool networkDown,
}) {
  final normalized = error.toString().toLowerCase();
  final message = compactCheckMessage(
    error is TimeoutException
        ? error.message ?? '${checkStageLabel(stage)}檢查超時'
        : errorText(error),
  );

  // 網站要真人勾選、封鎖了目前的網路或瀏覽器檢查沒過（CloudflareInterceptor）：
  // 夜讀不替使用者勾選，當成暫時不能用的書源，換網路或網站改設定後再校驗
  // 就會恢復。
  // 網域查不到：網站多半已經不在了。手機自己斷網時每個網域都查不到，
  // 這時當成連不上（[networkDown]）。
  if (hostNotFound(error) && !networkDown) {
    return CheckIssue(
      stage: 'upstream',
      message: '網域查不到，網站可能已經關了',
      health: upstreamHealth(siteBrokenSourceGroupTag),
    );
  }

  if (blockedBySite(error, normalized)) {
    return CheckIssue(
      stage: 'upstream',
      message: message,
      health: upstreamHealth(upstreamBlockedSourceGroupTag),
    );
  }

  // 書源要使用者驗證：校驗不跳畫面、不等人，只標狀態；閱讀時讓使用者
  // 自己去網頁上驗證（ADR 0038）。
  if (error is SourceVerificationException) {
    return CheckIssue(
      stage: stage,
      message: error.message,
      health: verificationRequiredSourceHealth,
    );
  }

  // 登入牆丟的錯誤（ADR 0038），或規則 JS 接住後改寫的同一句：只認登入牆
  // 那份明確的片語，也只看錯誤本身的訊息。解析錯誤後面接著規則與網址、
  // 連不上的接著主機名稱，網站叫 vipxs 這類時會被誤認成要登入。
  if (error is LoginCheckException ||
      (error is ParsingException &&
          error.originalError is LoginCheckException) ||
      StrResponse.mentionsLoginRequired(_ownMessage(error))) {
    return const CheckIssue(
      stage: 'content',
      message: '正文需要登入後閱讀',
      health: loginRequiredSourceHealth,
    );
  }

  if (_looksLikeTimeout(normalized)) {
    return CheckIssue(
      stage: 'timeout',
      message: '校驗超時或來源響應過慢',
      health: upstreamHealth(timeoutSourceGroupTag),
    );
  }

  if (_looksLikeBlockedUpstream(normalized)) {
    return CheckIssue(
      stage: 'upstream',
      message: message,
      health: upstreamHealth(upstreamBlockedSourceGroupTag),
    );
  }

  return CheckIssue(
    stage: stage,
    message: message,
    health: _brokenHealthFor(mode, stage),
  );
}

/// 錯誤本身的訊息，不含夜讀接在後面的規則、網址與原始錯誤。
String _ownMessage(Object error) => switch (error) {
  AppException(:final message) => message,
  DioException(:final message) => message ?? '',
  _ => '$error',
};

CheckIssue primaryIssue(List<CheckIssue> issues) {
  var primary = issues.first;
  for (final issue in issues.skip(1)) {
    if (_issuePriority(issue.health.category) >
        _issuePriority(primary.health.category)) {
      primary = issue;
    }
  }
  return primary;
}

String composeIssueMessage(List<CheckIssue> issues) {
  final seen = <String>{};
  final parts = <String>[];
  for (final issue in issues) {
    final part = '${checkStageLabel(issue.stage)}: ${issue.message}';
    if (seen.add(part)) parts.add(part);
  }
  return compactCheckMessage(parts.join('；'));
}

bool hasTerminalIssue(List<CheckIssue> issues) =>
    issues.any((i) => i.health.cleanupCandidate || i.health.quarantined);
