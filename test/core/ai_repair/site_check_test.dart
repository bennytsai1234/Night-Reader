import 'package:night_reader/core/models/source/source_site.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/site_check.dart';

const _origin = 'https://www.site.com';

SiteCheck _judge(SitePage home, {SitePage? missing}) =>
    judgeSite(origin: _origin, home: home, missing: missing);

SitePage _page(String body, {int status = 200, String? url}) =>
    SitePage(status: status, finalUrl: url ?? '$_origin/', body: body);

const _bookSite =
    '<html><body><div class="list"><a href="/b/1">第一本書</a>'
    '<a href="/b/2">第二本書</a></div></body></html>';

void main() {
  test('a domain that does not resolve is gone, unless the phone itself is '
      'offline', () {
    final check = _judge(const SitePage(error: 'Failed host lookup'));
    expect(check.verdict, SiteVerdict.gone);
    expect(check.detail, '網域查不到');

    final offline = judgeSite(
      origin: _origin,
      home: const SitePage(error: 'Failed host lookup'),
      networkUp: false,
    );
    expect(offline.verdict, SiteVerdict.unreachable);
  });

  test('a refused or dropped connection and a 5xx are unreachable', () {
    expect(
      _judge(const SitePage(error: 'Connection closed before full header'))
          .verdict,
      SiteVerdict.unreachable,
    );
    expect(
      _judge(_page('Bad gateway', status: 502)).verdict,
      SiteVerdict.unreachable,
    );
  });

  test('parked and for-sale domains are gone even though they answer 200', () {
    for (final body in [
      '<script>window.LANDER_SYSTEM="PW"</script>',
      '<script>fetch("https://router.parklogic.com/")</script>',
      '<h1>域名轉讓 一口价 CNY 3897.00</h1>',
    ]) {
      expect(_judge(_page(body)).verdict, SiteVerdict.gone, reason: body);
    }
  });

  test('a page that needs a browser to solve a challenge is blocked', () {
    expect(
      _judge(_page("<title>Making sure you're not a bot!</title> anubis"))
          .verdict,
      SiteVerdict.blocked,
    );
    expect(
      _judge(const SitePage(error: '網站的瀏覽器檢查沒有通過')).verdict,
      SiteVerdict.blocked,
    );
    expect(
      _judge(_page('<h3>防搜刮安全验证</h3><div>请计算 3 + 4 = ?</div>')).verdict,
      SiteVerdict.blocked,
    );
  });

  test('a home page that lands on another site means the site moved', () {
    final check = _judge(_page(_bookSite, url: 'https://m.newsite.net/'));
    expect(check.verdict, SiteVerdict.moved);
    expect(check.movedTo, 'https://m.newsite.net');
  });

  test('moving between www, m and https of the same site is not a move', () {
    expect(
      _judge(_page(_bookSite, url: 'https://m.site.com/')).verdict,
      SiteVerdict.alive,
    );
  });

  test('a small shell or fake data returned for every address is gone', () {
    const mock = '{"request_id":"mock","msg":"success","code":200,"data":{}}';
    final check = _judge(_page(mock), missing: _page(mock));
    expect(check.verdict, SiteVerdict.gone);
    expect(check.detail, contains('每個網址都回同一份內容'));
  });

  test('a real site answers a missing page differently and stays alive', () {
    expect(
      _judge(
        _page(_bookSite),
        missing: _page('Not found', status: 404),
      ).verdict,
      SiteVerdict.alive,
    );
  });

  test('a long page that happens to mention a domain sale is not a parked '
      'domain', () {
    final page =
        '$_bookSite${'<p class="ad">本站域名一口价出售中</p>' * 20}'
        '${'<a href="/b/9">好看的書</a>' * 200}';
    expect(_judge(_page(page)).verdict, SiteVerdict.alive);
  });

  test('a small shell that loads its content with a script is left to the '
      'AI', () {
    const app =
        '<html><body><div id="app"></div>'
        '<script src="/main.js"></script></body></html>';
    expect(_judge(_page(app), missing: _page(app)).verdict, SiteVerdict.alive);
  });

  test('a large page served for every address may be a single-page app, so '
      'it is left to the AI', () {
    final app = '<div id="app">${'<p class="x">書</p>' * 200}</div>';
    expect(_judge(_page(app), missing: _page(app)).verdict, SiteVerdict.alive);
  });

  test('the site address is the part before the path and markers', () {
    expect(siteOrigin('https://www.a.cc/#🎃'), 'https://www.a.cc');
    expect(
      siteOrigin('http://a.cc:8080,{"method":"POST"}'),
      'http://a.cc:8080',
    );
    expect(siteOrigin('a.cc'), isNull);
  });
}
