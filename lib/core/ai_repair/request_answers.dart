/// 一件修復裡每個請求回過什麼，找出時好時壞的（[record]）。
final class RequestAnswers {
  /// 這件修復裡每個請求回過什麼（狀態碼或「沒有回應」），從開場的校驗與
  /// 試抓起，照順序、同一段裡一樣的只記一次：一下成功、一下 429 或 5xx 的
  /// 網站，AI 每次成功就以為好了、接著修別段（2026-11-14 白光小说 36 輪
  /// 用完），程式把這個事實列在開場與結果後面，判斷照舊交給 AI。
  ///
  /// 同一個請求是方法、網址、送出的內容與標頭都一樣：只看網址時，白光的
  /// POST 少帶 submit 回 502、帶了 301，兩個不同的請求被當成時好時壞；換了
  /// User-Agent 就通是找到修法，也不算。校驗、試抓與工具的請求紀錄都記標頭
  /// （`RequestLog.sentHeaders`），開場校驗和試抓才對得上。
  final Map<String, List<String>> _answered = {};

  /// 請求那一行：GET 只寫網址，其他寫方法；轉址的下一跳在網址後面接
  /// 「（轉址）」，送出的內容寫在「送出：」後面，標頭寫在「標頭：」後面
  /// （`recordRequestUrl`）。
  static final RegExp _requestLine = RegExp(
    r'^(?:(POST|PUT|PATCH|DELETE|HEAD) )?(https?://[^\s（]+)(?:（轉址）)?'
    r'(?: 送出：(.*?))?(?: 標頭：(.*))?$',
  );

  static final RegExp _responseLine = RegExp(
    r'^ *← (?:頁 \d+｜)?(\S+) (\d{3}|沒有回應)',
  );

  static bool _ok(String status) =>
      status.length == 3 && (status.startsWith('2') || status.startsWith('3'));

  static bool _failed(String status) =>
      status == '沒有回應' || status == '429' || status.startsWith('5');

  /// 記下 [text] 裡的回應；其中有請求回過成功也回過失敗時，傳回列出它們的
  /// 一段，沒有是空字串。回應前面沒有請求那一行的不算（認不出是哪個請求）；
  /// 轉址後的下一跳是對新網址的 GET。
  String record(String text) {
    final seen = <String, Set<String>>{};
    ({String url, String key})? request;
    for (final line in text.split('\n')) {
      if (_requestLine.firstMatch(line) case final match?) {
        final method = match.group(1);
        final url = match.group(2)!;
        final body = match.group(3);
        final headers = match.group(4);
        request = (
          url: url,
          key:
              '${method == null ? '' : '$method '}$url'
              '${body == null ? '' : ' 送出：$body'}'
              '${headers == null ? '' : ' 標頭：$headers'}',
        );
        continue;
      }
      final response = _responseLine.firstMatch(line);
      if (response == null || request == null) continue;
      final url = response.group(1)!;
      final key = url == request.url ? request.key : url;
      seen.putIfAbsent(key, () => {}).add(response.group(2)!);
    }
    for (final MapEntry(key: key, value: statuses) in seen.entries) {
      _answered.putIfAbsent(key, () => []).addAll(statuses);
    }
    final lines = [
      for (final key in seen.keys)
        if (_answered[key]! case final all
            when all.any(_ok) && all.any(_failed))
          '$key：${all.join('、')}',
    ];
    return lines.isEmpty ? '' : '\n\n# 同一個請求這次回過不同的結果\n${lines.join('\n')}';
  }
}
