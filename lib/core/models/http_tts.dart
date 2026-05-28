import 'base_source.dart';

/// HttpTTS - 在線朗讀引擎模型
/// (原 Android data/entities/HttpTTS.kt)
class HttpTTS extends BaseSource {
  final int id;
  String name;
  String url;
  String? contentType;

  @override
  String? concurrentRate;

  @override
  String? loginUrl;

  @override
  String? loginUi;

  @override
  String? header;

  @override
  String? jsLib;

  @override
  bool enabledCookieJar;

  @override
  String? loginCheckJs;
  int lastUpdateTime;

  HttpTTS({
    required this.id,
    this.name = '',
    this.url = '',
    this.contentType,
    this.concurrentRate = '0',
    this.loginUrl,
    this.loginUi,
    this.header,
    this.jsLib,
    this.enabledCookieJar = false,
    this.loginCheckJs,
    this.lastUpdateTime = 0,
  });

  @override
  String getTag() => name;

  @override
  String getKey() => 'httpTts:$id';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'contentType': contentType,
      'concurrentRate': concurrentRate,
      'loginUrl': loginUrl,
      'loginUi': loginUi,
      'header': header,
      'jsLib': jsLib,
      'enabledCookieJar': enabledCookieJar ? 1 : 0,
      'loginCheckJs': loginCheckJs,
      'lastUpdateTime': lastUpdateTime,
    };
  }

  factory HttpTTS.fromJson(Map<String, dynamic> json) {
    return HttpTTS(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      contentType: json['contentType'],
      concurrentRate: json['concurrentRate'] ?? '0',
      loginUrl: json['loginUrl'],
      loginUi: json['loginUi'],
      header: json['header'],
      jsLib: json['jsLib'],
      enabledCookieJar:
          json['enabledCookieJar'] == 1 || json['enabledCookieJar'] == true,
      loginCheckJs: json['loginCheckJs'],
      lastUpdateTime: json['lastUpdateTime'] ?? 0,
    );
  }
}
