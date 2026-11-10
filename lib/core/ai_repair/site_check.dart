import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/network/page_digest.dart';
import 'package:night_reader/core/services/source_check_isolate.dart';
import 'package:night_reader/core/utils/public_suffix.dart';

/// 網站檢查的結論：書源校驗沒過時，問題在網站那邊，還是在規則。
enum SiteVerdict {
  /// 網站好好的，問題多半在規則：交給 AI。
  alive,

  /// 網站不在了：網域查不到、停放或出售、只剩空殼或假資料。
  gone,

  /// 首頁連不上或伺服器出錯。書源用的其他網址可能還好（實測 AI 修好過的
  /// 網站裡有首頁回 403、握手失敗的），所以照樣交給 AI。
  unreachable,

  /// 首頁轉到別的網域：網站搬家了（[SiteCheck.movedTo]）。
  moved,

  /// 首頁要瀏覽器算題目或真人驗證才放行。書源用的其他網址可能沒擋，照樣
  /// 交給 AI。
  blocked,
}

/// 一個網站的檢查結果。
class SiteCheck {
  const SiteCheck(this.verdict, this.detail, {this.movedTo});

  final SiteVerdict verdict;

  /// 給使用者看的一句，例如「網域查不到」「首頁轉到 www.new.com」。
  final String detail;

  /// 搬家時新網址的開頭（`https://www.new.com`）。
  final String? movedTo;

  Map<String, Object?> toMap() => {
    'verdict': verdict.name,
    'detail': detail,
    'movedTo': movedTo,
  };

  factory SiteCheck.fromMap(Map<Object?, Object?> map) => SiteCheck(
    SiteVerdict.values.byName(map['verdict']! as String),
    map['detail']! as String,
    movedTo: map['movedTo'] as String?,
  );
}

/// 抓到的一頁：狀態碼、轉址後的網址、內容；抓不到時是 [error]。
class SitePage {
  const SitePage({this.status, this.finalUrl, this.body = '', this.error});

  final int? status;
  final String? finalUrl;
  final String body;
  final String? error;

  Map<String, Object?> toMap() => {
    'status': status,
    'finalUrl': finalUrl,
    'body': body,
    'error': error,
  };

  factory SitePage.fromMap(Map<Object?, Object?> map) => SitePage(
    status: map['status'] as int?,
    finalUrl: map['finalUrl'] as String?,
    body: map['body'] as String? ?? '',
    error: map['error'] as String?,
  );
}

/// 照網站的首頁 [home] 與一個不存在的網址 [missing] 的回應判斷網站的狀況。
/// [origin] 是書源網址的開頭（`https://www.site.com`）。
SiteCheck judgeSite({
  required String origin,
  required SitePage home,
  SitePage? missing,
}) {
  final error = home.error;
  if (error != null) {
    if (error.contains('Failed host lookup')) {
      return const SiteCheck(SiteVerdict.gone, '網域查不到');
    }
    if (_blockedError.hasMatch(error)) {
      return SiteCheck(SiteVerdict.blocked, _short(error));
    }
    return SiteCheck(SiteVerdict.unreachable, '連不上：${_short(error)}');
  }
  final status = home.status ?? 0;
  final body = home.body;
  // 防護頁先認：它的腳本裡可能剛好有停放頁的字樣。
  if (_challenge.hasMatch(body)) {
    return const SiteCheck(SiteVerdict.blocked, '要在瀏覽器裡通過驗證才放行');
  }
  if (_parked.hasMatch(body)) {
    return const SiteCheck(SiteVerdict.gone, '網域停放或出售中');
  }
  if (status >= 500) {
    return SiteCheck(SiteVerdict.unreachable, '伺服器出錯（$status）');
  }
  final from = Uri.tryParse(origin)?.host ?? '';
  final to = Uri.tryParse(home.finalUrl ?? '')?.host ?? '';
  if (to.isNotEmpty && _site(to) != _site(from)) {
    final target = Uri.parse(home.finalUrl!);
    return SiteCheck(
      SiteVerdict.moved,
      '首頁轉到 $to',
      movedTo: '${target.scheme}://${target.authority}',
    );
  }
  final shell = digestPage(body);
  if (missing != null &&
      missing.error == null &&
      (missing.status ?? 0) < 400 &&
      shell.length < _shellLength &&
      digestPage(missing.body) == shell) {
    return SiteCheck(
      SiteVerdict.gone,
      shell.isEmpty ? '每個網址都回空白頁' : '每個網址都回同一份內容：${_short(shell)}',
    );
  }
  if (status >= 400 && shell.length < _shellLength) {
    return SiteCheck(SiteVerdict.unreachable, '首頁回 $status');
  }
  return const SiteCheck(SiteVerdict.alive, '網站正常回應');
}

/// 停放、出售網域的頁面：GoDaddy、Sedo、Bodis、ParkLogic 與中文的域名出售頁。
final RegExp _parked = RegExp(
  r'parking-lander|/lander\b|LANDER_SYSTEM|parklogic|sedoparking|bodis\.com|'
  r'dan\.com|afternic|hugedomains|domain (?:is )?for sale|'
  r'域名(?:出售|转让|轉讓|已过期|已到期)|此域名|该域名|一口价',
  caseSensitive: false,
);

/// 要瀏覽器算題目或人工勾選的防護頁。Cloudflare 的五秒盾夜讀會在背景的
/// 瀏覽器裡過（ADR 0033），過不了才會還是這一頁。
final RegExp _challenge = RegExp(
  r'anubis|making sure you(?:&#39;|’|'
  ')re not a bot|正在确认你是不是机器人|'
  r'<title>\s*just a moment|cf-chl-|challenge-platform',
  caseSensitive: false,
);

/// 夜讀抓網頁時網站擋下的錯誤（`CloudflareInterceptor`）。
final RegExp _blockedError = RegExp(r'瀏覽器檢查沒有通過|真人驗證|封鎖了目前的網路');

/// 精簡後短於這個字數的頁面才算空殼：每個網址都回同一份大網頁的，可能是
/// 單頁式網站，交給 AI 判斷。
const int _shellLength = 1000;

String _site(String host) => registrableDomain(host) ?? host;

String _short(String text) {
  final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return line.length <= 60 ? line : '${line.substring(0, 60)}…';
}

/// 檢查 [source] 的網站：照書源的標頭與 Cookie 抓首頁與一個不存在的網址
/// （在書源 worker 裡，和試抓一樣），交給 [judgeSite]。
Future<SiteCheck> checkSite(
  BookSource source, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final origin = siteOrigin(source.bookSourceUrl);
  if (origin == null) {
    return const SiteCheck(SiteVerdict.alive, '書源網址不是 http 開頭，不檢查');
  }
  final SourceWorker worker;
  try {
    worker = await SourceWorker.spawn(
      debugName: 'SiteCheck',
      withDictionaries: false,
    );
  } catch (error) {
    return SiteCheck(SiteVerdict.alive, '檢查不了：$error');
  }
  try {
    final map = await worker
        .run(_siteTask(source.toJson(), origin))
        .timeout(
          timeout,
          onTimeout: () => {'home': const SitePage(error: '檢查超過時間').toMap()},
        );
    return judgeSite(
      origin: origin,
      home: SitePage.fromMap(map['home']! as Map<Object?, Object?>),
      missing: switch (map['missing']) {
        final Map<Object?, Object?> page => SitePage.fromMap(page),
        _ => null,
      },
    );
  } catch (error) {
    return SiteCheck(SiteVerdict.alive, '檢查不了：$error');
  } finally {
    worker.kill(StateError('網站檢查已結束'));
  }
}

/// 書源網址的開頭（`https://www.site.com`）；不是 http(s) 的是 null。
String? siteOrigin(String sourceUrl) {
  final match = RegExp(
    r'^(https?://[^/#?,\s]+)',
    caseSensitive: false,
  ).firstMatch(sourceUrl.trim());
  return match?.group(1);
}

Future<Map<String, Object?>> Function(CancelToken) _siteTask(
  Map<String, dynamic> sourceJson,
  String origin,
) => (_) async {
  final source = BookSource.fromJson(sourceJson);
  Future<SitePage> fetch(String url) async {
    try {
      final response = await AnalyzeUrl(url, source: source).getStrResponse();
      return SitePage(
        status: response.raw.statusCode,
        finalUrl: response.url,
        body: response.body.length > _keptBody
            ? response.body.substring(0, _keptBody)
            : response.body,
      );
    } catch (error) {
      return SitePage(
        error: hostNotFound(error) ? 'Failed host lookup' : '$error',
      );
    }
  }

  final home = await fetch('$origin/');
  final probe = Random().nextInt(1 << 30).toRadixString(36);
  final missing = home.error == null
      ? await fetch('$origin/nr-missing-$probe.html')
      : null;
  return {'home': home.toMap(), 'missing': missing?.toMap()};
};

/// 每頁留多少字回主程式判斷：停放頁與防護頁的字樣都在開頭。
const int _keptBody = 200000;
