/// SearchKeyword - 搜尋關鍵字模型
/// (原 Android data/entities/SearchKeyword.kt)
class SearchKeyword {
  String word;
  int usage;
  int lastUseTime;

  SearchKeyword({this.word = '', this.usage = 1, this.lastUseTime = 0});

  Map<String, dynamic> toJson() {
    return {'word': word, 'usage': usage, 'lastUseTime': lastUseTime};
  }

  factory SearchKeyword.fromJson(Map<String, dynamic> json) {
    return SearchKeyword(
      word: json['word'] ?? '',
      usage: json['usage'] ?? 1,
      lastUseTime: json['lastUseTime'] ?? 0,
    );
  }
}
