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
    checkKeyWord: json['checkKeyWord'],
    bookList: json['bookList'],
    name: json['name'],
    author: json['author'],
    intro: json['intro'],
    kind: json['kind'],
    lastChapter: json['lastChapter'],
    updateTime: json['updateTime'],
    bookUrl: json['bookUrl'],
    coverUrl: json['coverUrl'],
    wordCount: json['wordCount'],
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
    bookList: json['bookList'],
    name: json['name'],
    author: json['author'],
    intro: json['intro'],
    kind: json['kind'],
    lastChapter: json['lastChapter'],
    updateTime: json['updateTime'],
    bookUrl: json['bookUrl'],
    coverUrl: json['coverUrl'],
    wordCount: json['wordCount'],
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
    init: json['init'],
    name: json['name'],
    author: json['author'],
    intro: json['intro'],
    kind: json['kind'],
    lastChapter: json['lastChapter'],
    updateTime: json['updateTime'],
    coverUrl: json['coverUrl'],
    tocUrl: json['tocUrl'],
    wordCount: json['wordCount'],
    canReName: json['canReName']?.toString(), // 原 Android 為 String?
    downloadUrls: json['downloadUrls'],
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
    preUpdateJs: json['preUpdateJs'],
    chapterList: json['chapterList'],
    chapterName: json['chapterName'],
    chapterUrl: json['chapterUrl'],
    formatJs: json['formatJs'],
    isVolume: json['isVolume']?.toString(),
    isVip: json['isVip']?.toString(),
    isPay: json['isPay']?.toString(),
    updateTime: json['updateTime'],
    nextTocUrl: json['nextTocUrl'] ?? json['nextPage'], // 相容舊版 nextPage
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
    content: json['content'],
    title: json['title'],
    nextContentUrl: json['nextContentUrl'] ?? json['nextPage'], // 相容舊版 nextPage
    webJs: json['webJs'],
    sourceRegex: json['sourceRegex'],
    replaceRegex: json['replaceRegex'] ?? json['replace'], // 相容舊版 replace
    imageStyle: json['imageStyle'],
    imageDecode: json['imageDecode'],
    payAction: json['payAction'],
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
    reviewUrl: json['reviewUrl'],
    avatarRule: json['avatarRule'],
    contentRule: json['contentRule'],
    postTimeRule: json['postTimeRule'],
    reviewQuoteUrl: json['reviewQuoteUrl'],
    voteUpUrl: json['voteUpUrl'],
    voteDownUrl: json['voteDownUrl'],
    postReviewUrl: json['postReviewUrl'],
    postQuoteUrl: json['postQuoteUrl'],
    deleteUrl: json['deleteUrl'],
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
