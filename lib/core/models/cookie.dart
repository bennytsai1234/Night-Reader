/// Cookie - Cookie 儲存模型
/// (原 Android data/entities/Cookie.kt)
class Cookie {
  String url;
  String cookie;

  Cookie({this.url = '', this.cookie = ''});

  Map<String, dynamic> toJson() {
    return {'url': url, 'cookie': cookie};
  }

  factory Cookie.fromJson(Map<String, dynamic> json) {
    return Cookie(url: json['url'] ?? '', cookie: json['cookie'] ?? '');
  }
}
