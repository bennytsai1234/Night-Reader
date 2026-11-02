import 'package:night_reader/core/models/json_read.dart';

/// BookSource 的子規則類別定義 (對齊 Android Legado rule/)
class SearchRule {
  String? checkKeyWord,
      bookList,
      name,
      author,
      intro,
      kind,
      lastChapter,
      updateTime,
      bookUrl,
      coverUrl,
      wordCount;

  SearchRule({
    this.checkKeyWord,
    this.bookList,
    this.name,
    this.author,
    this.intro,
    this.kind,
    this.lastChapter,
    this.updateTime,
    this.bookUrl,
    this.coverUrl,
    this.wordCount,
  });

  factory SearchRule.fromJson(Map<String, dynamic> json) => SearchRule(
    checkKeyWord: readJsonString(json['checkKeyWord']),
    bookList: readJsonString(json['bookList']),
    name: readJsonString(json['name']),
    author: readJsonString(json['author']),
    intro: readJsonString(json['intro']),
    kind: readJsonString(json['kind']),
    lastChapter: readJsonString(json['lastChapter']),
    updateTime: readJsonString(json['updateTime']),
    bookUrl: readJsonString(json['bookUrl']),
    coverUrl: readJsonString(json['coverUrl']),
    wordCount: readJsonString(json['wordCount']),
  );

  Map<String, dynamic> toJson() => {
    'checkKeyWord': checkKeyWord,
    'bookList': bookList,
    'name': name,
    'author': author,
    'intro': intro,
    'kind': kind,
    'lastChapter': lastChapter,
    'updateTime': updateTime,
    'bookUrl': bookUrl,
    'coverUrl': coverUrl,
    'wordCount': wordCount,
  };
}

class ExploreRule {
  String? bookList,
      name,
      author,
      intro,
      kind,
      lastChapter,
      updateTime,
      bookUrl,
      coverUrl,
      wordCount;

  ExploreRule({
    this.bookList,
    this.name,
    this.author,
    this.intro,
    this.kind,
    this.lastChapter,
    this.updateTime,
    this.bookUrl,
    this.coverUrl,
    this.wordCount,
  });

  factory ExploreRule.fromJson(Map<String, dynamic> json) => ExploreRule(
    bookList: readJsonString(json['bookList']),
    name: readJsonString(json['name']),
    author: readJsonString(json['author']),
    intro: readJsonString(json['intro']),
    kind: readJsonString(json['kind']),
    lastChapter: readJsonString(json['lastChapter']),
    updateTime: readJsonString(json['updateTime']),
    bookUrl: readJsonString(json['bookUrl']),
    coverUrl: readJsonString(json['coverUrl']),
    wordCount: readJsonString(json['wordCount']),
  );

  Map<String, dynamic> toJson() => {
    'bookList': bookList,
    'name': name,
    'author': author,
    'intro': intro,
    'kind': kind,
    'lastChapter': lastChapter,
    'updateTime': updateTime,
    'bookUrl': bookUrl,
    'coverUrl': coverUrl,
    'wordCount': wordCount,
  };
}

class BookInfoRule {
  String? init,
      name,
      author,
      intro,
      kind,
      lastChapter,
      updateTime,
      coverUrl,
      tocUrl,
      wordCount,
      canReName,
      downloadUrls;

  BookInfoRule({
    this.init,
    this.name,
    this.author,
    this.intro,
    this.kind,
    this.lastChapter,
    this.updateTime,
    this.coverUrl,
    this.tocUrl,
    this.wordCount,
    this.canReName,
    this.downloadUrls,
  });

  factory BookInfoRule.fromJson(Map<String, dynamic> json) => BookInfoRule(
    init: readJsonString(json['init']),
    name: readJsonString(json['name']),
    author: readJsonString(json['author']),
    intro: readJsonString(json['intro']),
    kind: readJsonString(json['kind']),
    lastChapter: readJsonString(json['lastChapter']),
    updateTime: readJsonString(json['updateTime']),
    coverUrl: readJsonString(json['coverUrl']),
    tocUrl: readJsonString(json['tocUrl']),
    wordCount: readJsonString(json['wordCount']),
    canReName: readJsonString(json['canReName']), // 原 Android 為 String?
    downloadUrls: readJsonString(json['downloadUrls']),
  );

  Map<String, dynamic> toJson() => {
    'init': init,
    'name': name,
    'author': author,
    'intro': intro,
    'kind': kind,
    'lastChapter': lastChapter,
    'updateTime': updateTime,
    'coverUrl': coverUrl,
    'tocUrl': tocUrl,
    'wordCount': wordCount,
    'canReName': canReName,
    'downloadUrls': downloadUrls,
  };
}

class TocRule {
  String? preUpdateJs,
      chapterList,
      chapterName,
      chapterUrl,
      formatJs,
      isVolume,
      isVip,
      isPay,
      updateTime,
      nextTocUrl;

  // --- UI 相容性別名 ---
  String? get nextPage => nextTocUrl;
  set nextPage(String? v) => nextTocUrl = v;

  TocRule({
    this.preUpdateJs,
    this.chapterList,
    this.chapterName,
    this.chapterUrl,
    this.formatJs,
    this.isVolume,
    this.isVip,
    this.isPay,
    this.updateTime,
    this.nextTocUrl,
  });

  factory TocRule.fromJson(Map<String, dynamic> json) => TocRule(
    preUpdateJs: readJsonString(json['preUpdateJs']),
    chapterList: readJsonString(json['chapterList']),
    chapterName: readJsonString(json['chapterName']),
    chapterUrl: readJsonString(json['chapterUrl']),
    formatJs: readJsonString(json['formatJs']),
    isVolume: readJsonString(json['isVolume']),
    isVip: readJsonString(json['isVip']),
    isPay: readJsonString(json['isPay']),
    updateTime: readJsonString(json['updateTime']),
    nextTocUrl:
        readJsonString(json['nextTocUrl']) ??
        readJsonString(json['nextPage']), // 相容舊版 nextPage
  );

  Map<String, dynamic> toJson() => {
    'preUpdateJs': preUpdateJs,
    'chapterList': chapterList,
    'chapterName': chapterName,
    'chapterUrl': chapterUrl,
    'formatJs': formatJs,
    'isVolume': isVolume,
    'isVip': isVip,
    'isPay': isPay,
    'updateTime': updateTime,
    'nextTocUrl': nextTocUrl,
  };
}

class ContentRule {
  String? content,
      title,
      nextContentUrl,
      webJs,
      sourceRegex,
      replaceRegex,
      imageStyle,
      imageDecode,
      payAction;

  // --- UI 相容性別名 ---
  String? get nextPage => nextContentUrl;
  set nextPage(String? v) => nextContentUrl = v;
  String? get replace => replaceRegex;
  set replace(String? v) => replaceRegex = v;

  ContentRule({
    this.content,
    this.title,
    this.nextContentUrl,
    this.webJs,
    this.sourceRegex,
    this.replaceRegex,
    this.imageStyle,
    this.imageDecode,
    this.payAction,
  });

  factory ContentRule.fromJson(Map<String, dynamic> json) => ContentRule(
    content: readJsonString(json['content']),
    title: readJsonString(json['title']),
    nextContentUrl:
        readJsonString(json['nextContentUrl']) ??
        readJsonString(json['nextPage']), // 相容舊版 nextPage
    webJs: readJsonString(json['webJs']),
    sourceRegex: readJsonString(json['sourceRegex']),
    replaceRegex:
        readJsonString(json['replaceRegex']) ??
        readJsonString(json['replace']), // 相容舊版 replace
    imageStyle: readJsonString(json['imageStyle']),
    imageDecode: readJsonString(json['imageDecode']),
    payAction: readJsonString(json['payAction']),
  );

  Map<String, dynamic> toJson() => {
    'content': content,
    'title': title,
    'nextContentUrl': nextContentUrl,
    'webJs': webJs,
    'sourceRegex': sourceRegex,
    'replaceRegex': replaceRegex,
    'imageStyle': imageStyle,
    'imageDecode': imageDecode,
    'payAction': payAction,
  };
}

class ReviewRule {
  String? reviewUrl,
      avatarRule,
      contentRule,
      postTimeRule,
      reviewQuoteUrl,
      voteUpUrl,
      voteDownUrl,
      postReviewUrl,
      postQuoteUrl,
      deleteUrl;

  ReviewRule({
    this.reviewUrl,
    this.avatarRule,
    this.contentRule,
    this.postTimeRule,
    this.reviewQuoteUrl,
    this.voteUpUrl,
    this.voteDownUrl,
    this.postReviewUrl,
    this.postQuoteUrl,
    this.deleteUrl,
  });

  factory ReviewRule.fromJson(Map<String, dynamic> json) => ReviewRule(
    reviewUrl: readJsonString(json['reviewUrl']),
    avatarRule: readJsonString(json['avatarRule']),
    contentRule: readJsonString(json['contentRule']),
    postTimeRule: readJsonString(json['postTimeRule']),
    reviewQuoteUrl: readJsonString(json['reviewQuoteUrl']),
    voteUpUrl: readJsonString(json['voteUpUrl']),
    voteDownUrl: readJsonString(json['voteDownUrl']),
    postReviewUrl: readJsonString(json['postReviewUrl']),
    postQuoteUrl: readJsonString(json['postQuoteUrl']),
    deleteUrl: readJsonString(json['deleteUrl']),
  );

  Map<String, dynamic> toJson() => {
    'reviewUrl': reviewUrl,
    'avatarRule': avatarRule,
    'contentRule': contentRule,
    'postTimeRule': postTimeRule,
    'reviewQuoteUrl': reviewQuoteUrl,
    'voteUpUrl': voteUpUrl,
    'voteDownUrl': voteDownUrl,
    'postReviewUrl': postReviewUrl,
    'postQuoteUrl': postQuoteUrl,
    'deleteUrl': deleteUrl,
  };
}
