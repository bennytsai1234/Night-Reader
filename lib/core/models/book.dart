import 'dart:convert';
import 'package:night_reader/core/models/rule_data_interface.dart';
import 'book/book_base.dart';
import 'book/book_serialization.dart';

export 'book/book_base.dart';
export 'book/book_extensions.dart';
export 'book/book_logic.dart';

/// Book - 書籍模型 (重構後)
/// (原 Android data/entities/Book.kt)
/// 透過繼承與 Extension 將邏輯拆分至各個子檔案
class Book extends BookBase implements RuleDataInterface {
  Book({
    super.bookUrl,
    super.tocUrl,
    super.origin,
    super.originName,
    super.name,
    super.author,
    super.kind,
    super.customTag,
    super.coverUrl,
    super.coverLocalPath,
    super.customCoverUrl,
    super.customCoverLocalPath,
    super.intro,
    super.customIntro,
    super.charset,
    super.type,
    super.group,
    super.latestChapterTitle,
    super.latestChapterTime,
    super.lastCheckTime,
    super.lastCheckCount,
    super.totalChapterNum,
    super.durChapterTitle,
    super.chapterIndex,
    super.charOffset,
    super.visualOffsetPx,
    super.readerAnchorJson,
    super.durChapterTime,
    super.wordCount,
    super.canUpdate,
    super.order,
    super.originOrder,
    super.variable,
    super.readConfig,
    super.syncTime,
    super.isInBookshelf,
  });

  @override
  Map<String, String> get variableMap {
    if (variable == null || variable!.isEmpty) return {};
    try {
      final decoded = jsonDecode(variable!);
      return (decoded as Map).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
    } catch (_) {
      return {};
    }
  }

  @override
  void putVariable(String key, String? value) {
    var map = variableMap;
    if (value == null) {
      map.remove(key);
    } else {
      map[key] = value;
    }
    variable = jsonEncode(map);
  }

  @override
  String getVariable(String key) => variableMap[key] ?? '';

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      bookUrl: json['bookUrl'] ?? '',
      tocUrl: json['tocUrl'] ?? '',
      origin: json['origin'] ?? 'local',
      originName: json['originName'] ?? '',
      name: json['name'] ?? '',
      author: json['author'] ?? '',
      kind: json['kind'],
      customTag: json['customTag'],
      coverUrl: json['coverUrl'],
      coverLocalPath: json['coverLocalPath'],
      customCoverUrl: json['customCoverUrl'],
      customCoverLocalPath: json['customCoverLocalPath'],
      intro: json['intro'],
      customIntro: json['customIntro'],
      charset: json['charset'],
      type: BookSerialization.toInt(json['type']),
      group: BookSerialization.toInt(json['group']),
      latestChapterTitle: json['latestChapterTitle'],
      latestChapterTime: BookSerialization.toInt(json['latestChapterTime']),
      lastCheckTime: BookSerialization.toInt(json['lastCheckTime']),
      lastCheckCount: BookSerialization.toInt(json['lastCheckCount']),
      totalChapterNum: BookSerialization.toInt(json['totalChapterNum']),
      durChapterTitle: json['durChapterTitle'],
      chapterIndex: BookSerialization.toInt(json['chapterIndex']),
      charOffset: BookSerialization.toInt(json['charOffset']),
      visualOffsetPx: BookSerialization.toVisualOffsetPx(
        json['visualOffsetPx'],
      ),
      readerAnchorJson: json['readerAnchorJson'],
      durChapterTime: BookSerialization.toInt(json['durChapterTime']),
      wordCount: json['wordCount'],
      canUpdate: json['canUpdate'] == 1 || json['canUpdate'] == true,
      order: BookSerialization.toInt(json['order']),
      originOrder: BookSerialization.toInt(json['originOrder']),
      variable: json['variable'],
      readConfig:
          json['readConfig'] != null
              ? ReadConfig.fromJson(
                json['readConfig'] is String
                    ? jsonDecode(json['readConfig'])
                    : json['readConfig'],
              )
              : null,
      syncTime: BookSerialization.toInt(json['syncTime']),
      isInBookshelf:
          json['isInBookshelf'] == 1 || json['isInBookshelf'] == true,
    );
  }

  Map<String, dynamic> toJson() => BookSerialization.bookToJson(this);

  Book copyWith({
    String? bookUrl,
    String? tocUrl,
    String? origin,
    String? originName,
    String? name,
    String? author,
    String? kind,
    String? customTag,
    String? coverUrl,
    String? coverLocalPath,
    String? customCoverUrl,
    String? customCoverLocalPath,
    String? intro,
    String? customIntro,
    String? charset,
    int? type,
    int? group,
    String? latestChapterTitle,
    int? latestChapterTime,
    int? lastCheckTime,
    int? lastCheckCount,
    int? totalChapterNum,
    String? durChapterTitle,
    int? chapterIndex,
    int? charOffset,
    double? visualOffsetPx,
    String? readerAnchorJson,
    int? durChapterTime,
    String? wordCount,
    bool? canUpdate,
    int? order,
    int? originOrder,
    String? variable,
    ReadConfig? readConfig,
    int? syncTime,
    bool? isInBookshelf,
  }) {
    return Book(
      bookUrl: bookUrl ?? this.bookUrl,
      tocUrl: tocUrl ?? this.tocUrl,
      origin: origin ?? this.origin,
      originName: originName ?? this.originName,
      name: name ?? this.name,
      author: author ?? this.author,
      kind: kind ?? this.kind,
      customTag: customTag ?? this.customTag,
      coverUrl: coverUrl ?? this.coverUrl,
      coverLocalPath: coverLocalPath ?? this.coverLocalPath,
      customCoverUrl: customCoverUrl ?? this.customCoverUrl,
      customCoverLocalPath: customCoverLocalPath ?? this.customCoverLocalPath,
      intro: intro ?? this.intro,
      customIntro: customIntro ?? this.customIntro,
      charset: charset ?? this.charset,
      type: type ?? this.type,
      group: group ?? this.group,
      latestChapterTitle: latestChapterTitle ?? this.latestChapterTitle,
      latestChapterTime: latestChapterTime ?? this.latestChapterTime,
      lastCheckTime: lastCheckTime ?? this.lastCheckTime,
      lastCheckCount: lastCheckCount ?? this.lastCheckCount,
      totalChapterNum: totalChapterNum ?? this.totalChapterNum,
      durChapterTitle: durChapterTitle ?? this.durChapterTitle,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      charOffset: charOffset ?? this.charOffset,
      visualOffsetPx: visualOffsetPx ?? this.visualOffsetPx,
      readerAnchorJson: readerAnchorJson ?? this.readerAnchorJson,
      durChapterTime: durChapterTime ?? this.durChapterTime,
      wordCount: wordCount ?? this.wordCount,
      canUpdate: canUpdate ?? this.canUpdate,
      order: order ?? this.order,
      originOrder: originOrder ?? this.originOrder,
      variable: variable ?? this.variable,
      readConfig: readConfig ?? this.readConfig,
      syncTime: syncTime ?? this.syncTime,
      isInBookshelf: isInBookshelf ?? this.isInBookshelf,
    );
  }
}
