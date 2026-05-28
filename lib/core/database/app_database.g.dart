// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $BooksTable extends Books with TableInfo<$BooksTable, Book> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookUrlMeta = const VerificationMeta(
    'bookUrl',
  );
  @override
  late final GeneratedColumn<String> bookUrl = GeneratedColumn<String>(
    'bookUrl',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<String, String> tocUrl =
      GeneratedColumn<String>(
        'tocUrl',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<String>($BooksTable.$convertertocUrl);
  @override
  late final GeneratedColumnWithTypeConverter<String, String> origin =
      GeneratedColumn<String>(
        'origin',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<String>($BooksTable.$converterorigin);
  @override
  late final GeneratedColumnWithTypeConverter<String, String> originName =
      GeneratedColumn<String>(
        'originName',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<String>($BooksTable.$converteroriginName);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<String, String> author =
      GeneratedColumn<String>(
        'author',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<String>($BooksTable.$converterauthor);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customTagMeta = const VerificationMeta(
    'customTag',
  );
  @override
  late final GeneratedColumn<String> customTag = GeneratedColumn<String>(
    'customTag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverUrlMeta = const VerificationMeta(
    'coverUrl',
  );
  @override
  late final GeneratedColumn<String> coverUrl = GeneratedColumn<String>(
    'coverUrl',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverLocalPathMeta = const VerificationMeta(
    'coverLocalPath',
  );
  @override
  late final GeneratedColumn<String> coverLocalPath = GeneratedColumn<String>(
    'coverLocalPath',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customCoverUrlMeta = const VerificationMeta(
    'customCoverUrl',
  );
  @override
  late final GeneratedColumn<String> customCoverUrl = GeneratedColumn<String>(
    'customCoverUrl',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customCoverLocalPathMeta =
      const VerificationMeta('customCoverLocalPath');
  @override
  late final GeneratedColumn<String> customCoverLocalPath =
      GeneratedColumn<String>(
        'customCoverLocalPath',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _introMeta = const VerificationMeta('intro');
  @override
  late final GeneratedColumn<String> intro = GeneratedColumn<String>(
    'intro',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customIntroMeta = const VerificationMeta(
    'customIntro',
  );
  @override
  late final GeneratedColumn<String> customIntro = GeneratedColumn<String>(
    'customIntro',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _charsetMeta = const VerificationMeta(
    'charset',
  );
  @override
  late final GeneratedColumn<String> charset = GeneratedColumn<String>(
    'charset',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _groupMeta = const VerificationMeta('group');
  @override
  late final GeneratedColumn<int> group = GeneratedColumn<int>(
    'group',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _latestChapterTitleMeta =
      const VerificationMeta('latestChapterTitle');
  @override
  late final GeneratedColumn<String> latestChapterTitle =
      GeneratedColumn<String>(
        'latestChapterTitle',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _latestChapterTimeMeta = const VerificationMeta(
    'latestChapterTime',
  );
  @override
  late final GeneratedColumn<int> latestChapterTime = GeneratedColumn<int>(
    'latestChapterTime',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastCheckTimeMeta = const VerificationMeta(
    'lastCheckTime',
  );
  @override
  late final GeneratedColumn<int> lastCheckTime = GeneratedColumn<int>(
    'lastCheckTime',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastCheckCountMeta = const VerificationMeta(
    'lastCheckCount',
  );
  @override
  late final GeneratedColumn<int> lastCheckCount = GeneratedColumn<int>(
    'lastCheckCount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalChapterNumMeta = const VerificationMeta(
    'totalChapterNum',
  );
  @override
  late final GeneratedColumn<int> totalChapterNum = GeneratedColumn<int>(
    'totalChapterNum',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durChapterTitleMeta = const VerificationMeta(
    'durChapterTitle',
  );
  @override
  late final GeneratedColumn<String> durChapterTitle = GeneratedColumn<String>(
    'durChapterTitle',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _chapterIndexMeta = const VerificationMeta(
    'chapterIndex',
  );
  @override
  late final GeneratedColumn<int> chapterIndex = GeneratedColumn<int>(
    'chapterIndex',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _charOffsetMeta = const VerificationMeta(
    'charOffset',
  );
  @override
  late final GeneratedColumn<int> charOffset = GeneratedColumn<int>(
    'charOffset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _visualOffsetPxMeta = const VerificationMeta(
    'visualOffsetPx',
  );
  @override
  late final GeneratedColumn<double> visualOffsetPx = GeneratedColumn<double>(
    'visualOffsetPx',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _readerAnchorJsonMeta = const VerificationMeta(
    'readerAnchorJson',
  );
  @override
  late final GeneratedColumn<String> readerAnchorJson = GeneratedColumn<String>(
    'readerAnchorJson',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durChapterTimeMeta = const VerificationMeta(
    'durChapterTime',
  );
  @override
  late final GeneratedColumn<int> durChapterTime = GeneratedColumn<int>(
    'durChapterTime',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _wordCountMeta = const VerificationMeta(
    'wordCount',
  );
  @override
  late final GeneratedColumn<String> wordCount = GeneratedColumn<String>(
    'wordCount',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _canUpdateMeta = const VerificationMeta(
    'canUpdate',
  );
  @override
  late final GeneratedColumn<bool> canUpdate = GeneratedColumn<bool>(
    'canUpdate',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("canUpdate" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _orderMeta = const VerificationMeta('order');
  @override
  late final GeneratedColumn<int> order = GeneratedColumn<int>(
    'order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _originOrderMeta = const VerificationMeta(
    'originOrder',
  );
  @override
  late final GeneratedColumn<int> originOrder = GeneratedColumn<int>(
    'originOrder',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _variableMeta = const VerificationMeta(
    'variable',
  );
  @override
  late final GeneratedColumn<String> variable = GeneratedColumn<String>(
    'variable',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ReadConfig?, String> readConfig =
      GeneratedColumn<String>(
        'readConfig',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<ReadConfig?>($BooksTable.$converterreadConfig);
  static const VerificationMeta _syncTimeMeta = const VerificationMeta(
    'syncTime',
  );
  @override
  late final GeneratedColumn<int> syncTime = GeneratedColumn<int>(
    'syncTime',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isInBookshelfMeta = const VerificationMeta(
    'isInBookshelf',
  );
  @override
  late final GeneratedColumn<bool> isInBookshelf = GeneratedColumn<bool>(
    'isInBookshelf',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("isInBookshelf" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    bookUrl,
    tocUrl,
    origin,
    originName,
    name,
    author,
    kind,
    customTag,
    coverUrl,
    coverLocalPath,
    customCoverUrl,
    customCoverLocalPath,
    intro,
    customIntro,
    charset,
    type,
    group,
    latestChapterTitle,
    latestChapterTime,
    lastCheckTime,
    lastCheckCount,
    totalChapterNum,
    durChapterTitle,
    chapterIndex,
    charOffset,
    visualOffsetPx,
    readerAnchorJson,
    durChapterTime,
    wordCount,
    canUpdate,
    order,
    originOrder,
    variable,
    readConfig,
    syncTime,
    isInBookshelf,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'books';
  @override
  VerificationContext validateIntegrity(
    Insertable<Book> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('bookUrl')) {
      context.handle(
        _bookUrlMeta,
        bookUrl.isAcceptableOrUnknown(data['bookUrl']!, _bookUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_bookUrlMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('customTag')) {
      context.handle(
        _customTagMeta,
        customTag.isAcceptableOrUnknown(data['customTag']!, _customTagMeta),
      );
    }
    if (data.containsKey('coverUrl')) {
      context.handle(
        _coverUrlMeta,
        coverUrl.isAcceptableOrUnknown(data['coverUrl']!, _coverUrlMeta),
      );
    }
    if (data.containsKey('coverLocalPath')) {
      context.handle(
        _coverLocalPathMeta,
        coverLocalPath.isAcceptableOrUnknown(
          data['coverLocalPath']!,
          _coverLocalPathMeta,
        ),
      );
    }
    if (data.containsKey('customCoverUrl')) {
      context.handle(
        _customCoverUrlMeta,
        customCoverUrl.isAcceptableOrUnknown(
          data['customCoverUrl']!,
          _customCoverUrlMeta,
        ),
      );
    }
    if (data.containsKey('customCoverLocalPath')) {
      context.handle(
        _customCoverLocalPathMeta,
        customCoverLocalPath.isAcceptableOrUnknown(
          data['customCoverLocalPath']!,
          _customCoverLocalPathMeta,
        ),
      );
    }
    if (data.containsKey('intro')) {
      context.handle(
        _introMeta,
        intro.isAcceptableOrUnknown(data['intro']!, _introMeta),
      );
    }
    if (data.containsKey('customIntro')) {
      context.handle(
        _customIntroMeta,
        customIntro.isAcceptableOrUnknown(
          data['customIntro']!,
          _customIntroMeta,
        ),
      );
    }
    if (data.containsKey('charset')) {
      context.handle(
        _charsetMeta,
        charset.isAcceptableOrUnknown(data['charset']!, _charsetMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('group')) {
      context.handle(
        _groupMeta,
        group.isAcceptableOrUnknown(data['group']!, _groupMeta),
      );
    }
    if (data.containsKey('latestChapterTitle')) {
      context.handle(
        _latestChapterTitleMeta,
        latestChapterTitle.isAcceptableOrUnknown(
          data['latestChapterTitle']!,
          _latestChapterTitleMeta,
        ),
      );
    }
    if (data.containsKey('latestChapterTime')) {
      context.handle(
        _latestChapterTimeMeta,
        latestChapterTime.isAcceptableOrUnknown(
          data['latestChapterTime']!,
          _latestChapterTimeMeta,
        ),
      );
    }
    if (data.containsKey('lastCheckTime')) {
      context.handle(
        _lastCheckTimeMeta,
        lastCheckTime.isAcceptableOrUnknown(
          data['lastCheckTime']!,
          _lastCheckTimeMeta,
        ),
      );
    }
    if (data.containsKey('lastCheckCount')) {
      context.handle(
        _lastCheckCountMeta,
        lastCheckCount.isAcceptableOrUnknown(
          data['lastCheckCount']!,
          _lastCheckCountMeta,
        ),
      );
    }
    if (data.containsKey('totalChapterNum')) {
      context.handle(
        _totalChapterNumMeta,
        totalChapterNum.isAcceptableOrUnknown(
          data['totalChapterNum']!,
          _totalChapterNumMeta,
        ),
      );
    }
    if (data.containsKey('durChapterTitle')) {
      context.handle(
        _durChapterTitleMeta,
        durChapterTitle.isAcceptableOrUnknown(
          data['durChapterTitle']!,
          _durChapterTitleMeta,
        ),
      );
    }
    if (data.containsKey('chapterIndex')) {
      context.handle(
        _chapterIndexMeta,
        chapterIndex.isAcceptableOrUnknown(
          data['chapterIndex']!,
          _chapterIndexMeta,
        ),
      );
    }
    if (data.containsKey('charOffset')) {
      context.handle(
        _charOffsetMeta,
        charOffset.isAcceptableOrUnknown(data['charOffset']!, _charOffsetMeta),
      );
    }
    if (data.containsKey('visualOffsetPx')) {
      context.handle(
        _visualOffsetPxMeta,
        visualOffsetPx.isAcceptableOrUnknown(
          data['visualOffsetPx']!,
          _visualOffsetPxMeta,
        ),
      );
    }
    if (data.containsKey('readerAnchorJson')) {
      context.handle(
        _readerAnchorJsonMeta,
        readerAnchorJson.isAcceptableOrUnknown(
          data['readerAnchorJson']!,
          _readerAnchorJsonMeta,
        ),
      );
    }
    if (data.containsKey('durChapterTime')) {
      context.handle(
        _durChapterTimeMeta,
        durChapterTime.isAcceptableOrUnknown(
          data['durChapterTime']!,
          _durChapterTimeMeta,
        ),
      );
    }
    if (data.containsKey('wordCount')) {
      context.handle(
        _wordCountMeta,
        wordCount.isAcceptableOrUnknown(data['wordCount']!, _wordCountMeta),
      );
    }
    if (data.containsKey('canUpdate')) {
      context.handle(
        _canUpdateMeta,
        canUpdate.isAcceptableOrUnknown(data['canUpdate']!, _canUpdateMeta),
      );
    }
    if (data.containsKey('order')) {
      context.handle(
        _orderMeta,
        order.isAcceptableOrUnknown(data['order']!, _orderMeta),
      );
    }
    if (data.containsKey('originOrder')) {
      context.handle(
        _originOrderMeta,
        originOrder.isAcceptableOrUnknown(
          data['originOrder']!,
          _originOrderMeta,
        ),
      );
    }
    if (data.containsKey('variable')) {
      context.handle(
        _variableMeta,
        variable.isAcceptableOrUnknown(data['variable']!, _variableMeta),
      );
    }
    if (data.containsKey('syncTime')) {
      context.handle(
        _syncTimeMeta,
        syncTime.isAcceptableOrUnknown(data['syncTime']!, _syncTimeMeta),
      );
    }
    if (data.containsKey('isInBookshelf')) {
      context.handle(
        _isInBookshelfMeta,
        isInBookshelf.isAcceptableOrUnknown(
          data['isInBookshelf']!,
          _isInBookshelfMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookUrl};
  @override
  Book map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Book(
      bookUrl:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}bookUrl'],
          )!,
      tocUrl: $BooksTable.$convertertocUrl.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}tocUrl'],
        ),
      ),
      origin: $BooksTable.$converterorigin.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}origin'],
        ),
      ),
      originName: $BooksTable.$converteroriginName.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}originName'],
        ),
      ),
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      author: $BooksTable.$converterauthor.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}author'],
        ),
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      ),
      customTag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customTag'],
      ),
      coverUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coverUrl'],
      ),
      coverLocalPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coverLocalPath'],
      ),
      customCoverUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customCoverUrl'],
      ),
      customCoverLocalPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customCoverLocalPath'],
      ),
      intro: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intro'],
      ),
      customIntro: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customIntro'],
      ),
      charset: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}charset'],
      ),
      type:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}type'],
          )!,
      group:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}group'],
          )!,
      latestChapterTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}latestChapterTitle'],
      ),
      latestChapterTime:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}latestChapterTime'],
          )!,
      lastCheckTime:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}lastCheckTime'],
          )!,
      lastCheckCount:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}lastCheckCount'],
          )!,
      totalChapterNum:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}totalChapterNum'],
          )!,
      durChapterTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}durChapterTitle'],
      ),
      chapterIndex:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}chapterIndex'],
          )!,
      charOffset:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}charOffset'],
          )!,
      visualOffsetPx:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}visualOffsetPx'],
          )!,
      readerAnchorJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}readerAnchorJson'],
      ),
      durChapterTime:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}durChapterTime'],
          )!,
      wordCount: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wordCount'],
      ),
      canUpdate:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}canUpdate'],
          )!,
      order:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}order'],
          )!,
      originOrder:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}originOrder'],
          )!,
      variable: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variable'],
      ),
      readConfig: $BooksTable.$converterreadConfig.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}readConfig'],
        ),
      ),
      syncTime:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}syncTime'],
          )!,
      isInBookshelf:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}isInBookshelf'],
          )!,
    );
  }

  @override
  $BooksTable createAlias(String alias) {
    return $BooksTable(attachedDatabase, alias);
  }

  static TypeConverter<String, String?> $convertertocUrl =
      const EmptyStringConverter();
  static TypeConverter<String, String?> $converterorigin =
      const EmptyStringConverter();
  static TypeConverter<String, String?> $converteroriginName =
      const EmptyStringConverter();
  static TypeConverter<String, String?> $converterauthor =
      const EmptyStringConverter();
  static TypeConverter<ReadConfig?, String?> $converterreadConfig =
      const ReadConfigConverter();
}

class BooksCompanion extends UpdateCompanion<Book> {
  final Value<String> bookUrl;
  final Value<String> tocUrl;
  final Value<String> origin;
  final Value<String> originName;
  final Value<String> name;
  final Value<String> author;
  final Value<String?> kind;
  final Value<String?> customTag;
  final Value<String?> coverUrl;
  final Value<String?> coverLocalPath;
  final Value<String?> customCoverUrl;
  final Value<String?> customCoverLocalPath;
  final Value<String?> intro;
  final Value<String?> customIntro;
  final Value<String?> charset;
  final Value<int> type;
  final Value<int> group;
  final Value<String?> latestChapterTitle;
  final Value<int> latestChapterTime;
  final Value<int> lastCheckTime;
  final Value<int> lastCheckCount;
  final Value<int> totalChapterNum;
  final Value<String?> durChapterTitle;
  final Value<int> chapterIndex;
  final Value<int> charOffset;
  final Value<double> visualOffsetPx;
  final Value<String?> readerAnchorJson;
  final Value<int> durChapterTime;
  final Value<String?> wordCount;
  final Value<bool> canUpdate;
  final Value<int> order;
  final Value<int> originOrder;
  final Value<String?> variable;
  final Value<ReadConfig?> readConfig;
  final Value<int> syncTime;
  final Value<bool> isInBookshelf;
  final Value<int> rowid;
  const BooksCompanion({
    this.bookUrl = const Value.absent(),
    this.tocUrl = const Value.absent(),
    this.origin = const Value.absent(),
    this.originName = const Value.absent(),
    this.name = const Value.absent(),
    this.author = const Value.absent(),
    this.kind = const Value.absent(),
    this.customTag = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.coverLocalPath = const Value.absent(),
    this.customCoverUrl = const Value.absent(),
    this.customCoverLocalPath = const Value.absent(),
    this.intro = const Value.absent(),
    this.customIntro = const Value.absent(),
    this.charset = const Value.absent(),
    this.type = const Value.absent(),
    this.group = const Value.absent(),
    this.latestChapterTitle = const Value.absent(),
    this.latestChapterTime = const Value.absent(),
    this.lastCheckTime = const Value.absent(),
    this.lastCheckCount = const Value.absent(),
    this.totalChapterNum = const Value.absent(),
    this.durChapterTitle = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.charOffset = const Value.absent(),
    this.visualOffsetPx = const Value.absent(),
    this.readerAnchorJson = const Value.absent(),
    this.durChapterTime = const Value.absent(),
    this.wordCount = const Value.absent(),
    this.canUpdate = const Value.absent(),
    this.order = const Value.absent(),
    this.originOrder = const Value.absent(),
    this.variable = const Value.absent(),
    this.readConfig = const Value.absent(),
    this.syncTime = const Value.absent(),
    this.isInBookshelf = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BooksCompanion.insert({
    required String bookUrl,
    this.tocUrl = const Value.absent(),
    this.origin = const Value.absent(),
    this.originName = const Value.absent(),
    required String name,
    this.author = const Value.absent(),
    this.kind = const Value.absent(),
    this.customTag = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.coverLocalPath = const Value.absent(),
    this.customCoverUrl = const Value.absent(),
    this.customCoverLocalPath = const Value.absent(),
    this.intro = const Value.absent(),
    this.customIntro = const Value.absent(),
    this.charset = const Value.absent(),
    this.type = const Value.absent(),
    this.group = const Value.absent(),
    this.latestChapterTitle = const Value.absent(),
    this.latestChapterTime = const Value.absent(),
    this.lastCheckTime = const Value.absent(),
    this.lastCheckCount = const Value.absent(),
    this.totalChapterNum = const Value.absent(),
    this.durChapterTitle = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.charOffset = const Value.absent(),
    this.visualOffsetPx = const Value.absent(),
    this.readerAnchorJson = const Value.absent(),
    this.durChapterTime = const Value.absent(),
    this.wordCount = const Value.absent(),
    this.canUpdate = const Value.absent(),
    this.order = const Value.absent(),
    this.originOrder = const Value.absent(),
    this.variable = const Value.absent(),
    this.readConfig = const Value.absent(),
    this.syncTime = const Value.absent(),
    this.isInBookshelf = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : bookUrl = Value(bookUrl),
       name = Value(name);
  static Insertable<Book> custom({
    Expression<String>? bookUrl,
    Expression<String>? tocUrl,
    Expression<String>? origin,
    Expression<String>? originName,
    Expression<String>? name,
    Expression<String>? author,
    Expression<String>? kind,
    Expression<String>? customTag,
    Expression<String>? coverUrl,
    Expression<String>? coverLocalPath,
    Expression<String>? customCoverUrl,
    Expression<String>? customCoverLocalPath,
    Expression<String>? intro,
    Expression<String>? customIntro,
    Expression<String>? charset,
    Expression<int>? type,
    Expression<int>? group,
    Expression<String>? latestChapterTitle,
    Expression<int>? latestChapterTime,
    Expression<int>? lastCheckTime,
    Expression<int>? lastCheckCount,
    Expression<int>? totalChapterNum,
    Expression<String>? durChapterTitle,
    Expression<int>? chapterIndex,
    Expression<int>? charOffset,
    Expression<double>? visualOffsetPx,
    Expression<String>? readerAnchorJson,
    Expression<int>? durChapterTime,
    Expression<String>? wordCount,
    Expression<bool>? canUpdate,
    Expression<int>? order,
    Expression<int>? originOrder,
    Expression<String>? variable,
    Expression<String>? readConfig,
    Expression<int>? syncTime,
    Expression<bool>? isInBookshelf,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookUrl != null) 'bookUrl': bookUrl,
      if (tocUrl != null) 'tocUrl': tocUrl,
      if (origin != null) 'origin': origin,
      if (originName != null) 'originName': originName,
      if (name != null) 'name': name,
      if (author != null) 'author': author,
      if (kind != null) 'kind': kind,
      if (customTag != null) 'customTag': customTag,
      if (coverUrl != null) 'coverUrl': coverUrl,
      if (coverLocalPath != null) 'coverLocalPath': coverLocalPath,
      if (customCoverUrl != null) 'customCoverUrl': customCoverUrl,
      if (customCoverLocalPath != null)
        'customCoverLocalPath': customCoverLocalPath,
      if (intro != null) 'intro': intro,
      if (customIntro != null) 'customIntro': customIntro,
      if (charset != null) 'charset': charset,
      if (type != null) 'type': type,
      if (group != null) 'group': group,
      if (latestChapterTitle != null) 'latestChapterTitle': latestChapterTitle,
      if (latestChapterTime != null) 'latestChapterTime': latestChapterTime,
      if (lastCheckTime != null) 'lastCheckTime': lastCheckTime,
      if (lastCheckCount != null) 'lastCheckCount': lastCheckCount,
      if (totalChapterNum != null) 'totalChapterNum': totalChapterNum,
      if (durChapterTitle != null) 'durChapterTitle': durChapterTitle,
      if (chapterIndex != null) 'chapterIndex': chapterIndex,
      if (charOffset != null) 'charOffset': charOffset,
      if (visualOffsetPx != null) 'visualOffsetPx': visualOffsetPx,
      if (readerAnchorJson != null) 'readerAnchorJson': readerAnchorJson,
      if (durChapterTime != null) 'durChapterTime': durChapterTime,
      if (wordCount != null) 'wordCount': wordCount,
      if (canUpdate != null) 'canUpdate': canUpdate,
      if (order != null) 'order': order,
      if (originOrder != null) 'originOrder': originOrder,
      if (variable != null) 'variable': variable,
      if (readConfig != null) 'readConfig': readConfig,
      if (syncTime != null) 'syncTime': syncTime,
      if (isInBookshelf != null) 'isInBookshelf': isInBookshelf,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BooksCompanion copyWith({
    Value<String>? bookUrl,
    Value<String>? tocUrl,
    Value<String>? origin,
    Value<String>? originName,
    Value<String>? name,
    Value<String>? author,
    Value<String?>? kind,
    Value<String?>? customTag,
    Value<String?>? coverUrl,
    Value<String?>? coverLocalPath,
    Value<String?>? customCoverUrl,
    Value<String?>? customCoverLocalPath,
    Value<String?>? intro,
    Value<String?>? customIntro,
    Value<String?>? charset,
    Value<int>? type,
    Value<int>? group,
    Value<String?>? latestChapterTitle,
    Value<int>? latestChapterTime,
    Value<int>? lastCheckTime,
    Value<int>? lastCheckCount,
    Value<int>? totalChapterNum,
    Value<String?>? durChapterTitle,
    Value<int>? chapterIndex,
    Value<int>? charOffset,
    Value<double>? visualOffsetPx,
    Value<String?>? readerAnchorJson,
    Value<int>? durChapterTime,
    Value<String?>? wordCount,
    Value<bool>? canUpdate,
    Value<int>? order,
    Value<int>? originOrder,
    Value<String?>? variable,
    Value<ReadConfig?>? readConfig,
    Value<int>? syncTime,
    Value<bool>? isInBookshelf,
    Value<int>? rowid,
  }) {
    return BooksCompanion(
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
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookUrl.present) {
      map['bookUrl'] = Variable<String>(bookUrl.value);
    }
    if (tocUrl.present) {
      map['tocUrl'] = Variable<String>(
        $BooksTable.$convertertocUrl.toSql(tocUrl.value),
      );
    }
    if (origin.present) {
      map['origin'] = Variable<String>(
        $BooksTable.$converterorigin.toSql(origin.value),
      );
    }
    if (originName.present) {
      map['originName'] = Variable<String>(
        $BooksTable.$converteroriginName.toSql(originName.value),
      );
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(
        $BooksTable.$converterauthor.toSql(author.value),
      );
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (customTag.present) {
      map['customTag'] = Variable<String>(customTag.value);
    }
    if (coverUrl.present) {
      map['coverUrl'] = Variable<String>(coverUrl.value);
    }
    if (coverLocalPath.present) {
      map['coverLocalPath'] = Variable<String>(coverLocalPath.value);
    }
    if (customCoverUrl.present) {
      map['customCoverUrl'] = Variable<String>(customCoverUrl.value);
    }
    if (customCoverLocalPath.present) {
      map['customCoverLocalPath'] = Variable<String>(
        customCoverLocalPath.value,
      );
    }
    if (intro.present) {
      map['intro'] = Variable<String>(intro.value);
    }
    if (customIntro.present) {
      map['customIntro'] = Variable<String>(customIntro.value);
    }
    if (charset.present) {
      map['charset'] = Variable<String>(charset.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(type.value);
    }
    if (group.present) {
      map['group'] = Variable<int>(group.value);
    }
    if (latestChapterTitle.present) {
      map['latestChapterTitle'] = Variable<String>(latestChapterTitle.value);
    }
    if (latestChapterTime.present) {
      map['latestChapterTime'] = Variable<int>(latestChapterTime.value);
    }
    if (lastCheckTime.present) {
      map['lastCheckTime'] = Variable<int>(lastCheckTime.value);
    }
    if (lastCheckCount.present) {
      map['lastCheckCount'] = Variable<int>(lastCheckCount.value);
    }
    if (totalChapterNum.present) {
      map['totalChapterNum'] = Variable<int>(totalChapterNum.value);
    }
    if (durChapterTitle.present) {
      map['durChapterTitle'] = Variable<String>(durChapterTitle.value);
    }
    if (chapterIndex.present) {
      map['chapterIndex'] = Variable<int>(chapterIndex.value);
    }
    if (charOffset.present) {
      map['charOffset'] = Variable<int>(charOffset.value);
    }
    if (visualOffsetPx.present) {
      map['visualOffsetPx'] = Variable<double>(visualOffsetPx.value);
    }
    if (readerAnchorJson.present) {
      map['readerAnchorJson'] = Variable<String>(readerAnchorJson.value);
    }
    if (durChapterTime.present) {
      map['durChapterTime'] = Variable<int>(durChapterTime.value);
    }
    if (wordCount.present) {
      map['wordCount'] = Variable<String>(wordCount.value);
    }
    if (canUpdate.present) {
      map['canUpdate'] = Variable<bool>(canUpdate.value);
    }
    if (order.present) {
      map['order'] = Variable<int>(order.value);
    }
    if (originOrder.present) {
      map['originOrder'] = Variable<int>(originOrder.value);
    }
    if (variable.present) {
      map['variable'] = Variable<String>(variable.value);
    }
    if (readConfig.present) {
      map['readConfig'] = Variable<String>(
        $BooksTable.$converterreadConfig.toSql(readConfig.value),
      );
    }
    if (syncTime.present) {
      map['syncTime'] = Variable<int>(syncTime.value);
    }
    if (isInBookshelf.present) {
      map['isInBookshelf'] = Variable<bool>(isInBookshelf.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BooksCompanion(')
          ..write('bookUrl: $bookUrl, ')
          ..write('tocUrl: $tocUrl, ')
          ..write('origin: $origin, ')
          ..write('originName: $originName, ')
          ..write('name: $name, ')
          ..write('author: $author, ')
          ..write('kind: $kind, ')
          ..write('customTag: $customTag, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('coverLocalPath: $coverLocalPath, ')
          ..write('customCoverUrl: $customCoverUrl, ')
          ..write('customCoverLocalPath: $customCoverLocalPath, ')
          ..write('intro: $intro, ')
          ..write('customIntro: $customIntro, ')
          ..write('charset: $charset, ')
          ..write('type: $type, ')
          ..write('group: $group, ')
          ..write('latestChapterTitle: $latestChapterTitle, ')
          ..write('latestChapterTime: $latestChapterTime, ')
          ..write('lastCheckTime: $lastCheckTime, ')
          ..write('lastCheckCount: $lastCheckCount, ')
          ..write('totalChapterNum: $totalChapterNum, ')
          ..write('durChapterTitle: $durChapterTitle, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('charOffset: $charOffset, ')
          ..write('visualOffsetPx: $visualOffsetPx, ')
          ..write('readerAnchorJson: $readerAnchorJson, ')
          ..write('durChapterTime: $durChapterTime, ')
          ..write('wordCount: $wordCount, ')
          ..write('canUpdate: $canUpdate, ')
          ..write('order: $order, ')
          ..write('originOrder: $originOrder, ')
          ..write('variable: $variable, ')
          ..write('readConfig: $readConfig, ')
          ..write('syncTime: $syncTime, ')
          ..write('isInBookshelf: $isInBookshelf, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class _$BookInsertable implements Insertable<Book> {
  Book _object;
  _$BookInsertable(this._object);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return BooksCompanion(
      bookUrl: Value(_object.bookUrl),
      tocUrl: Value(_object.tocUrl),
      origin: Value(_object.origin),
      originName: Value(_object.originName),
      name: Value(_object.name),
      author: Value(_object.author),
      kind: Value(_object.kind),
      customTag: Value(_object.customTag),
      coverUrl: Value(_object.coverUrl),
      coverLocalPath: Value(_object.coverLocalPath),
      customCoverUrl: Value(_object.customCoverUrl),
      customCoverLocalPath: Value(_object.customCoverLocalPath),
      intro: Value(_object.intro),
      customIntro: Value(_object.customIntro),
      charset: Value(_object.charset),
      type: Value(_object.type),
      group: Value(_object.group),
      latestChapterTitle: Value(_object.latestChapterTitle),
      latestChapterTime: Value(_object.latestChapterTime),
      lastCheckTime: Value(_object.lastCheckTime),
      lastCheckCount: Value(_object.lastCheckCount),
      totalChapterNum: Value(_object.totalChapterNum),
      durChapterTitle: Value(_object.durChapterTitle),
      chapterIndex: Value(_object.chapterIndex),
      charOffset: Value(_object.charOffset),
      visualOffsetPx: Value(_object.visualOffsetPx),
      readerAnchorJson: Value(_object.readerAnchorJson),
      durChapterTime: Value(_object.durChapterTime),
      wordCount: Value(_object.wordCount),
      canUpdate: Value(_object.canUpdate),
      order: Value(_object.order),
      originOrder: Value(_object.originOrder),
      variable: Value(_object.variable),
      readConfig: Value(_object.readConfig),
      syncTime: Value(_object.syncTime),
      isInBookshelf: Value(_object.isInBookshelf),
    ).toColumns(false);
  }
}

extension BookToInsertable on Book {
  _$BookInsertable toInsertable() {
    return _$BookInsertable(this);
  }
}

class $ChaptersTable extends Chapters
    with TableInfo<$ChaptersTable, BookChapter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChaptersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isVolumeMeta = const VerificationMeta(
    'isVolume',
  );
  @override
  late final GeneratedColumn<bool> isVolume = GeneratedColumn<bool>(
    'isVolume',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("isVolume" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<String, String> baseUrl =
      GeneratedColumn<String>(
        'baseUrl',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<String>($ChaptersTable.$converterbaseUrl);
  static const VerificationMeta _bookUrlMeta = const VerificationMeta(
    'bookUrl',
  );
  @override
  late final GeneratedColumn<String> bookUrl = GeneratedColumn<String>(
    'bookUrl',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _indexMeta = const VerificationMeta('index');
  @override
  late final GeneratedColumn<int> index = GeneratedColumn<int>(
    'index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isVipMeta = const VerificationMeta('isVip');
  @override
  late final GeneratedColumn<bool> isVip = GeneratedColumn<bool>(
    'isVip',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("isVip" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isPayMeta = const VerificationMeta('isPay');
  @override
  late final GeneratedColumn<bool> isPay = GeneratedColumn<bool>(
    'isPay',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("isPay" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _resourceUrlMeta = const VerificationMeta(
    'resourceUrl',
  );
  @override
  late final GeneratedColumn<String> resourceUrl = GeneratedColumn<String>(
    'resourceUrl',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tagMeta = const VerificationMeta('tag');
  @override
  late final GeneratedColumn<String> tag = GeneratedColumn<String>(
    'tag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _wordCountMeta = const VerificationMeta(
    'wordCount',
  );
  @override
  late final GeneratedColumn<String> wordCount = GeneratedColumn<String>(
    'wordCount',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startMeta = const VerificationMeta('start');
  @override
  late final GeneratedColumn<int> start = GeneratedColumn<int>(
    'start',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endMeta = const VerificationMeta('end');
  @override
  late final GeneratedColumn<int> end = GeneratedColumn<int>(
    'end',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startFragmentIdMeta = const VerificationMeta(
    'startFragmentId',
  );
  @override
  late final GeneratedColumn<String> startFragmentId = GeneratedColumn<String>(
    'startFragmentId',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endFragmentIdMeta = const VerificationMeta(
    'endFragmentId',
  );
  @override
  late final GeneratedColumn<String> endFragmentId = GeneratedColumn<String>(
    'endFragmentId',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _variableMeta = const VerificationMeta(
    'variable',
  );
  @override
  late final GeneratedColumn<String> variable = GeneratedColumn<String>(
    'variable',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    url,
    title,
    isVolume,
    baseUrl,
    bookUrl,
    index,
    isVip,
    isPay,
    resourceUrl,
    tag,
    wordCount,
    start,
    end,
    startFragmentId,
    endFragmentId,
    variable,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chapters';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookChapter> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('isVolume')) {
      context.handle(
        _isVolumeMeta,
        isVolume.isAcceptableOrUnknown(data['isVolume']!, _isVolumeMeta),
      );
    }
    if (data.containsKey('bookUrl')) {
      context.handle(
        _bookUrlMeta,
        bookUrl.isAcceptableOrUnknown(data['bookUrl']!, _bookUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_bookUrlMeta);
    }
    if (data.containsKey('index')) {
      context.handle(
        _indexMeta,
        index.isAcceptableOrUnknown(data['index']!, _indexMeta),
      );
    } else if (isInserting) {
      context.missing(_indexMeta);
    }
    if (data.containsKey('isVip')) {
      context.handle(
        _isVipMeta,
        isVip.isAcceptableOrUnknown(data['isVip']!, _isVipMeta),
      );
    }
    if (data.containsKey('isPay')) {
      context.handle(
        _isPayMeta,
        isPay.isAcceptableOrUnknown(data['isPay']!, _isPayMeta),
      );
    }
    if (data.containsKey('resourceUrl')) {
      context.handle(
        _resourceUrlMeta,
        resourceUrl.isAcceptableOrUnknown(
          data['resourceUrl']!,
          _resourceUrlMeta,
        ),
      );
    }
    if (data.containsKey('tag')) {
      context.handle(
        _tagMeta,
        tag.isAcceptableOrUnknown(data['tag']!, _tagMeta),
      );
    }
    if (data.containsKey('wordCount')) {
      context.handle(
        _wordCountMeta,
        wordCount.isAcceptableOrUnknown(data['wordCount']!, _wordCountMeta),
      );
    }
    if (data.containsKey('start')) {
      context.handle(
        _startMeta,
        start.isAcceptableOrUnknown(data['start']!, _startMeta),
      );
    }
    if (data.containsKey('end')) {
      context.handle(
        _endMeta,
        end.isAcceptableOrUnknown(data['end']!, _endMeta),
      );
    }
    if (data.containsKey('startFragmentId')) {
      context.handle(
        _startFragmentIdMeta,
        startFragmentId.isAcceptableOrUnknown(
          data['startFragmentId']!,
          _startFragmentIdMeta,
        ),
      );
    }
    if (data.containsKey('endFragmentId')) {
      context.handle(
        _endFragmentIdMeta,
        endFragmentId.isAcceptableOrUnknown(
          data['endFragmentId']!,
          _endFragmentIdMeta,
        ),
      );
    }
    if (data.containsKey('variable')) {
      context.handle(
        _variableMeta,
        variable.isAcceptableOrUnknown(data['variable']!, _variableMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {url};
  @override
  BookChapter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookChapter(
      url:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}url'],
          )!,
      title:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}title'],
          )!,
      isVolume:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}isVolume'],
          )!,
      baseUrl: $ChaptersTable.$converterbaseUrl.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}baseUrl'],
        ),
      ),
      bookUrl:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}bookUrl'],
          )!,
      index:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}index'],
          )!,
      isVip:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}isVip'],
          )!,
      isPay:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}isPay'],
          )!,
      resourceUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resourceUrl'],
      ),
      tag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag'],
      ),
      wordCount: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wordCount'],
      ),
      start: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start'],
      ),
      end: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end'],
      ),
      startFragmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}startFragmentId'],
      ),
      endFragmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}endFragmentId'],
      ),
      variable: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variable'],
      ),
    );
  }

  @override
  $ChaptersTable createAlias(String alias) {
    return $ChaptersTable(attachedDatabase, alias);
  }

  static TypeConverter<String, String?> $converterbaseUrl =
      const EmptyStringConverter();
}

class ChaptersCompanion extends UpdateCompanion<BookChapter> {
  final Value<String> url;
  final Value<String> title;
  final Value<bool> isVolume;
  final Value<String> baseUrl;
  final Value<String> bookUrl;
  final Value<int> index;
  final Value<bool> isVip;
  final Value<bool> isPay;
  final Value<String?> resourceUrl;
  final Value<String?> tag;
  final Value<String?> wordCount;
  final Value<int?> start;
  final Value<int?> end;
  final Value<String?> startFragmentId;
  final Value<String?> endFragmentId;
  final Value<String?> variable;
  final Value<int> rowid;
  const ChaptersCompanion({
    this.url = const Value.absent(),
    this.title = const Value.absent(),
    this.isVolume = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.bookUrl = const Value.absent(),
    this.index = const Value.absent(),
    this.isVip = const Value.absent(),
    this.isPay = const Value.absent(),
    this.resourceUrl = const Value.absent(),
    this.tag = const Value.absent(),
    this.wordCount = const Value.absent(),
    this.start = const Value.absent(),
    this.end = const Value.absent(),
    this.startFragmentId = const Value.absent(),
    this.endFragmentId = const Value.absent(),
    this.variable = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChaptersCompanion.insert({
    required String url,
    required String title,
    this.isVolume = const Value.absent(),
    this.baseUrl = const Value.absent(),
    required String bookUrl,
    required int index,
    this.isVip = const Value.absent(),
    this.isPay = const Value.absent(),
    this.resourceUrl = const Value.absent(),
    this.tag = const Value.absent(),
    this.wordCount = const Value.absent(),
    this.start = const Value.absent(),
    this.end = const Value.absent(),
    this.startFragmentId = const Value.absent(),
    this.endFragmentId = const Value.absent(),
    this.variable = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : url = Value(url),
       title = Value(title),
       bookUrl = Value(bookUrl),
       index = Value(index);
  static Insertable<BookChapter> custom({
    Expression<String>? url,
    Expression<String>? title,
    Expression<bool>? isVolume,
    Expression<String>? baseUrl,
    Expression<String>? bookUrl,
    Expression<int>? index,
    Expression<bool>? isVip,
    Expression<bool>? isPay,
    Expression<String>? resourceUrl,
    Expression<String>? tag,
    Expression<String>? wordCount,
    Expression<int>? start,
    Expression<int>? end,
    Expression<String>? startFragmentId,
    Expression<String>? endFragmentId,
    Expression<String>? variable,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (url != null) 'url': url,
      if (title != null) 'title': title,
      if (isVolume != null) 'isVolume': isVolume,
      if (baseUrl != null) 'baseUrl': baseUrl,
      if (bookUrl != null) 'bookUrl': bookUrl,
      if (index != null) 'index': index,
      if (isVip != null) 'isVip': isVip,
      if (isPay != null) 'isPay': isPay,
      if (resourceUrl != null) 'resourceUrl': resourceUrl,
      if (tag != null) 'tag': tag,
      if (wordCount != null) 'wordCount': wordCount,
      if (start != null) 'start': start,
      if (end != null) 'end': end,
      if (startFragmentId != null) 'startFragmentId': startFragmentId,
      if (endFragmentId != null) 'endFragmentId': endFragmentId,
      if (variable != null) 'variable': variable,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChaptersCompanion copyWith({
    Value<String>? url,
    Value<String>? title,
    Value<bool>? isVolume,
    Value<String>? baseUrl,
    Value<String>? bookUrl,
    Value<int>? index,
    Value<bool>? isVip,
    Value<bool>? isPay,
    Value<String?>? resourceUrl,
    Value<String?>? tag,
    Value<String?>? wordCount,
    Value<int?>? start,
    Value<int?>? end,
    Value<String?>? startFragmentId,
    Value<String?>? endFragmentId,
    Value<String?>? variable,
    Value<int>? rowid,
  }) {
    return ChaptersCompanion(
      url: url ?? this.url,
      title: title ?? this.title,
      isVolume: isVolume ?? this.isVolume,
      baseUrl: baseUrl ?? this.baseUrl,
      bookUrl: bookUrl ?? this.bookUrl,
      index: index ?? this.index,
      isVip: isVip ?? this.isVip,
      isPay: isPay ?? this.isPay,
      resourceUrl: resourceUrl ?? this.resourceUrl,
      tag: tag ?? this.tag,
      wordCount: wordCount ?? this.wordCount,
      start: start ?? this.start,
      end: end ?? this.end,
      startFragmentId: startFragmentId ?? this.startFragmentId,
      endFragmentId: endFragmentId ?? this.endFragmentId,
      variable: variable ?? this.variable,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (isVolume.present) {
      map['isVolume'] = Variable<bool>(isVolume.value);
    }
    if (baseUrl.present) {
      map['baseUrl'] = Variable<String>(
        $ChaptersTable.$converterbaseUrl.toSql(baseUrl.value),
      );
    }
    if (bookUrl.present) {
      map['bookUrl'] = Variable<String>(bookUrl.value);
    }
    if (index.present) {
      map['index'] = Variable<int>(index.value);
    }
    if (isVip.present) {
      map['isVip'] = Variable<bool>(isVip.value);
    }
    if (isPay.present) {
      map['isPay'] = Variable<bool>(isPay.value);
    }
    if (resourceUrl.present) {
      map['resourceUrl'] = Variable<String>(resourceUrl.value);
    }
    if (tag.present) {
      map['tag'] = Variable<String>(tag.value);
    }
    if (wordCount.present) {
      map['wordCount'] = Variable<String>(wordCount.value);
    }
    if (start.present) {
      map['start'] = Variable<int>(start.value);
    }
    if (end.present) {
      map['end'] = Variable<int>(end.value);
    }
    if (startFragmentId.present) {
      map['startFragmentId'] = Variable<String>(startFragmentId.value);
    }
    if (endFragmentId.present) {
      map['endFragmentId'] = Variable<String>(endFragmentId.value);
    }
    if (variable.present) {
      map['variable'] = Variable<String>(variable.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChaptersCompanion(')
          ..write('url: $url, ')
          ..write('title: $title, ')
          ..write('isVolume: $isVolume, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('bookUrl: $bookUrl, ')
          ..write('index: $index, ')
          ..write('isVip: $isVip, ')
          ..write('isPay: $isPay, ')
          ..write('resourceUrl: $resourceUrl, ')
          ..write('tag: $tag, ')
          ..write('wordCount: $wordCount, ')
          ..write('start: $start, ')
          ..write('end: $end, ')
          ..write('startFragmentId: $startFragmentId, ')
          ..write('endFragmentId: $endFragmentId, ')
          ..write('variable: $variable, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class _$BookChapterInsertable implements Insertable<BookChapter> {
  BookChapter _object;
  _$BookChapterInsertable(this._object);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return ChaptersCompanion(
      url: Value(_object.url),
      title: Value(_object.title),
      isVolume: Value(_object.isVolume),
      baseUrl: Value(_object.baseUrl),
      bookUrl: Value(_object.bookUrl),
      index: Value(_object.index),
      isVip: Value(_object.isVip),
      isPay: Value(_object.isPay),
      resourceUrl: Value(_object.resourceUrl),
      tag: Value(_object.tag),
      wordCount: Value(_object.wordCount),
      start: Value(_object.start),
      end: Value(_object.end),
      startFragmentId: Value(_object.startFragmentId),
      endFragmentId: Value(_object.endFragmentId),
      variable: Value(_object.variable),
    ).toColumns(false);
  }
}

extension BookChapterToInsertable on BookChapter {
  _$BookChapterInsertable toInsertable() {
    return _$BookChapterInsertable(this);
  }
}

class $ReaderChapterContentsTable extends ReaderChapterContents
    with TableInfo<$ReaderChapterContentsTable, ReaderChapterContent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReaderChapterContentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _contentKeyMeta = const VerificationMeta(
    'contentKey',
  );
  @override
  late final GeneratedColumn<String> contentKey = GeneratedColumn<String>(
    'contentKey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookUrlMeta = const VerificationMeta(
    'bookUrl',
  );
  @override
  late final GeneratedColumn<String> bookUrl = GeneratedColumn<String>(
    'bookUrl',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterUrlMeta = const VerificationMeta(
    'chapterUrl',
  );
  @override
  late final GeneratedColumn<String> chapterUrl = GeneratedColumn<String>(
    'chapterUrl',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterIndexMeta = const VerificationMeta(
    'chapterIndex',
  );
  @override
  late final GeneratedColumn<int> chapterIndex = GeneratedColumn<int>(
    'chapterIndex',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _failureMessageMeta = const VerificationMeta(
    'failureMessage',
  );
  @override
  late final GeneratedColumn<String> failureMessage = GeneratedColumn<String>(
    'failureMessage',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updatedAt',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    contentKey,
    origin,
    bookUrl,
    chapterUrl,
    chapterIndex,
    content,
    status,
    failureMessage,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reader_chapter_contents';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReaderChapterContent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('contentKey')) {
      context.handle(
        _contentKeyMeta,
        contentKey.isAcceptableOrUnknown(data['contentKey']!, _contentKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_contentKeyMeta);
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    } else if (isInserting) {
      context.missing(_originMeta);
    }
    if (data.containsKey('bookUrl')) {
      context.handle(
        _bookUrlMeta,
        bookUrl.isAcceptableOrUnknown(data['bookUrl']!, _bookUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_bookUrlMeta);
    }
    if (data.containsKey('chapterUrl')) {
      context.handle(
        _chapterUrlMeta,
        chapterUrl.isAcceptableOrUnknown(data['chapterUrl']!, _chapterUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_chapterUrlMeta);
    }
    if (data.containsKey('chapterIndex')) {
      context.handle(
        _chapterIndexMeta,
        chapterIndex.isAcceptableOrUnknown(
          data['chapterIndex']!,
          _chapterIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_chapterIndexMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('failureMessage')) {
      context.handle(
        _failureMessageMeta,
        failureMessage.isAcceptableOrUnknown(
          data['failureMessage']!,
          _failureMessageMeta,
        ),
      );
    }
    if (data.containsKey('updatedAt')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updatedAt']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {contentKey};
  @override
  ReaderChapterContent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReaderChapterContent(
      contentKey:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}contentKey'],
          )!,
      origin:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}origin'],
          )!,
      bookUrl:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}bookUrl'],
          )!,
      chapterUrl:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}chapterUrl'],
          )!,
      chapterIndex:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}chapterIndex'],
          )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      ),
      status:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}status'],
          )!,
      failureMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failureMessage'],
      ),
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}updatedAt'],
          )!,
    );
  }

  @override
  $ReaderChapterContentsTable createAlias(String alias) {
    return $ReaderChapterContentsTable(attachedDatabase, alias);
  }
}

class ReaderChapterContent extends DataClass
    implements Insertable<ReaderChapterContent> {
  final String contentKey;
  final String origin;
  final String bookUrl;
  final String chapterUrl;
  final int chapterIndex;
  final String? content;
  final int status;
  final String? failureMessage;
  final int updatedAt;
  const ReaderChapterContent({
    required this.contentKey,
    required this.origin,
    required this.bookUrl,
    required this.chapterUrl,
    required this.chapterIndex,
    this.content,
    required this.status,
    this.failureMessage,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['contentKey'] = Variable<String>(contentKey);
    map['origin'] = Variable<String>(origin);
    map['bookUrl'] = Variable<String>(bookUrl);
    map['chapterUrl'] = Variable<String>(chapterUrl);
    map['chapterIndex'] = Variable<int>(chapterIndex);
    if (!nullToAbsent || content != null) {
      map['content'] = Variable<String>(content);
    }
    map['status'] = Variable<int>(status);
    if (!nullToAbsent || failureMessage != null) {
      map['failureMessage'] = Variable<String>(failureMessage);
    }
    map['updatedAt'] = Variable<int>(updatedAt);
    return map;
  }

  ReaderChapterContentsCompanion toCompanion(bool nullToAbsent) {
    return ReaderChapterContentsCompanion(
      contentKey: Value(contentKey),
      origin: Value(origin),
      bookUrl: Value(bookUrl),
      chapterUrl: Value(chapterUrl),
      chapterIndex: Value(chapterIndex),
      content:
          content == null && nullToAbsent
              ? const Value.absent()
              : Value(content),
      status: Value(status),
      failureMessage:
          failureMessage == null && nullToAbsent
              ? const Value.absent()
              : Value(failureMessage),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReaderChapterContent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReaderChapterContent(
      contentKey: serializer.fromJson<String>(json['contentKey']),
      origin: serializer.fromJson<String>(json['origin']),
      bookUrl: serializer.fromJson<String>(json['bookUrl']),
      chapterUrl: serializer.fromJson<String>(json['chapterUrl']),
      chapterIndex: serializer.fromJson<int>(json['chapterIndex']),
      content: serializer.fromJson<String?>(json['content']),
      status: serializer.fromJson<int>(json['status']),
      failureMessage: serializer.fromJson<String?>(json['failureMessage']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'contentKey': serializer.toJson<String>(contentKey),
      'origin': serializer.toJson<String>(origin),
      'bookUrl': serializer.toJson<String>(bookUrl),
      'chapterUrl': serializer.toJson<String>(chapterUrl),
      'chapterIndex': serializer.toJson<int>(chapterIndex),
      'content': serializer.toJson<String?>(content),
      'status': serializer.toJson<int>(status),
      'failureMessage': serializer.toJson<String?>(failureMessage),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  ReaderChapterContent copyWith({
    String? contentKey,
    String? origin,
    String? bookUrl,
    String? chapterUrl,
    int? chapterIndex,
    Value<String?> content = const Value.absent(),
    int? status,
    Value<String?> failureMessage = const Value.absent(),
    int? updatedAt,
  }) => ReaderChapterContent(
    contentKey: contentKey ?? this.contentKey,
    origin: origin ?? this.origin,
    bookUrl: bookUrl ?? this.bookUrl,
    chapterUrl: chapterUrl ?? this.chapterUrl,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    content: content.present ? content.value : this.content,
    status: status ?? this.status,
    failureMessage:
        failureMessage.present ? failureMessage.value : this.failureMessage,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReaderChapterContent copyWithCompanion(ReaderChapterContentsCompanion data) {
    return ReaderChapterContent(
      contentKey:
          data.contentKey.present ? data.contentKey.value : this.contentKey,
      origin: data.origin.present ? data.origin.value : this.origin,
      bookUrl: data.bookUrl.present ? data.bookUrl.value : this.bookUrl,
      chapterUrl:
          data.chapterUrl.present ? data.chapterUrl.value : this.chapterUrl,
      chapterIndex:
          data.chapterIndex.present
              ? data.chapterIndex.value
              : this.chapterIndex,
      content: data.content.present ? data.content.value : this.content,
      status: data.status.present ? data.status.value : this.status,
      failureMessage:
          data.failureMessage.present
              ? data.failureMessage.value
              : this.failureMessage,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReaderChapterContent(')
          ..write('contentKey: $contentKey, ')
          ..write('origin: $origin, ')
          ..write('bookUrl: $bookUrl, ')
          ..write('chapterUrl: $chapterUrl, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('content: $content, ')
          ..write('status: $status, ')
          ..write('failureMessage: $failureMessage, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    contentKey,
    origin,
    bookUrl,
    chapterUrl,
    chapterIndex,
    content,
    status,
    failureMessage,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReaderChapterContent &&
          other.contentKey == this.contentKey &&
          other.origin == this.origin &&
          other.bookUrl == this.bookUrl &&
          other.chapterUrl == this.chapterUrl &&
          other.chapterIndex == this.chapterIndex &&
          other.content == this.content &&
          other.status == this.status &&
          other.failureMessage == this.failureMessage &&
          other.updatedAt == this.updatedAt);
}

class ReaderChapterContentsCompanion
    extends UpdateCompanion<ReaderChapterContent> {
  final Value<String> contentKey;
  final Value<String> origin;
  final Value<String> bookUrl;
  final Value<String> chapterUrl;
  final Value<int> chapterIndex;
  final Value<String?> content;
  final Value<int> status;
  final Value<String?> failureMessage;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const ReaderChapterContentsCompanion({
    this.contentKey = const Value.absent(),
    this.origin = const Value.absent(),
    this.bookUrl = const Value.absent(),
    this.chapterUrl = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.content = const Value.absent(),
    this.status = const Value.absent(),
    this.failureMessage = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReaderChapterContentsCompanion.insert({
    required String contentKey,
    required String origin,
    required String bookUrl,
    required String chapterUrl,
    required int chapterIndex,
    this.content = const Value.absent(),
    this.status = const Value.absent(),
    this.failureMessage = const Value.absent(),
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : contentKey = Value(contentKey),
       origin = Value(origin),
       bookUrl = Value(bookUrl),
       chapterUrl = Value(chapterUrl),
       chapterIndex = Value(chapterIndex),
       updatedAt = Value(updatedAt);
  static Insertable<ReaderChapterContent> custom({
    Expression<String>? contentKey,
    Expression<String>? origin,
    Expression<String>? bookUrl,
    Expression<String>? chapterUrl,
    Expression<int>? chapterIndex,
    Expression<String>? content,
    Expression<int>? status,
    Expression<String>? failureMessage,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (contentKey != null) 'contentKey': contentKey,
      if (origin != null) 'origin': origin,
      if (bookUrl != null) 'bookUrl': bookUrl,
      if (chapterUrl != null) 'chapterUrl': chapterUrl,
      if (chapterIndex != null) 'chapterIndex': chapterIndex,
      if (content != null) 'content': content,
      if (status != null) 'status': status,
      if (failureMessage != null) 'failureMessage': failureMessage,
      if (updatedAt != null) 'updatedAt': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReaderChapterContentsCompanion copyWith({
    Value<String>? contentKey,
    Value<String>? origin,
    Value<String>? bookUrl,
    Value<String>? chapterUrl,
    Value<int>? chapterIndex,
    Value<String?>? content,
    Value<int>? status,
    Value<String?>? failureMessage,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return ReaderChapterContentsCompanion(
      contentKey: contentKey ?? this.contentKey,
      origin: origin ?? this.origin,
      bookUrl: bookUrl ?? this.bookUrl,
      chapterUrl: chapterUrl ?? this.chapterUrl,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      content: content ?? this.content,
      status: status ?? this.status,
      failureMessage: failureMessage ?? this.failureMessage,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (contentKey.present) {
      map['contentKey'] = Variable<String>(contentKey.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (bookUrl.present) {
      map['bookUrl'] = Variable<String>(bookUrl.value);
    }
    if (chapterUrl.present) {
      map['chapterUrl'] = Variable<String>(chapterUrl.value);
    }
    if (chapterIndex.present) {
      map['chapterIndex'] = Variable<int>(chapterIndex.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (failureMessage.present) {
      map['failureMessage'] = Variable<String>(failureMessage.value);
    }
    if (updatedAt.present) {
      map['updatedAt'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReaderChapterContentsCompanion(')
          ..write('contentKey: $contentKey, ')
          ..write('origin: $origin, ')
          ..write('bookUrl: $bookUrl, ')
          ..write('chapterUrl: $chapterUrl, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('content: $content, ')
          ..write('status: $status, ')
          ..write('failureMessage: $failureMessage, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookSourcesTable extends BookSources
    with TableInfo<$BookSourcesTable, BookSource> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookSourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookSourceUrlMeta = const VerificationMeta(
    'bookSourceUrl',
  );
  @override
  late final GeneratedColumn<String> bookSourceUrl = GeneratedColumn<String>(
    'bookSourceUrl',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookSourceNameMeta = const VerificationMeta(
    'bookSourceName',
  );
  @override
  late final GeneratedColumn<String> bookSourceName = GeneratedColumn<String>(
    'bookSourceName',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookSourceTypeMeta = const VerificationMeta(
    'bookSourceType',
  );
  @override
  late final GeneratedColumn<int> bookSourceType = GeneratedColumn<int>(
    'bookSourceType',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _bookSourceGroupMeta = const VerificationMeta(
    'bookSourceGroup',
  );
  @override
  late final GeneratedColumn<String> bookSourceGroup = GeneratedColumn<String>(
    'bookSourceGroup',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bookSourceCommentMeta = const VerificationMeta(
    'bookSourceComment',
  );
  @override
  late final GeneratedColumn<String> bookSourceComment =
      GeneratedColumn<String>(
        'bookSourceComment',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _loginUrlMeta = const VerificationMeta(
    'loginUrl',
  );
  @override
  late final GeneratedColumn<String> loginUrl = GeneratedColumn<String>(
    'loginUrl',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _loginUiMeta = const VerificationMeta(
    'loginUi',
  );
  @override
  late final GeneratedColumn<String> loginUi = GeneratedColumn<String>(
    'loginUi',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _loginCheckJsMeta = const VerificationMeta(
    'loginCheckJs',
  );
  @override
  late final GeneratedColumn<String> loginCheckJs = GeneratedColumn<String>(
    'loginCheckJs',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverDecodeJsMeta = const VerificationMeta(
    'coverDecodeJs',
  );
  @override
  late final GeneratedColumn<String> coverDecodeJs = GeneratedColumn<String>(
    'coverDecodeJs',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bookUrlPatternMeta = const VerificationMeta(
    'bookUrlPattern',
  );
  @override
  late final GeneratedColumn<String> bookUrlPattern = GeneratedColumn<String>(
    'bookUrlPattern',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _headerMeta = const VerificationMeta('header');
  @override
  late final GeneratedColumn<String> header = GeneratedColumn<String>(
    'header',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _variableCommentMeta = const VerificationMeta(
    'variableComment',
  );
  @override
  late final GeneratedColumn<String> variableComment = GeneratedColumn<String>(
    'variableComment',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customOrderMeta = const VerificationMeta(
    'customOrder',
  );
  @override
  late final GeneratedColumn<int> customOrder = GeneratedColumn<int>(
    'customOrder',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _weightMeta = const VerificationMeta('weight');
  @override
  late final GeneratedColumn<int> weight = GeneratedColumn<int>(
    'weight',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _enabledExploreMeta = const VerificationMeta(
    'enabledExplore',
  );
  @override
  late final GeneratedColumn<bool> enabledExplore = GeneratedColumn<bool>(
    'enabledExplore',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabledExplore" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _enabledCookieJarMeta = const VerificationMeta(
    'enabledCookieJar',
  );
  @override
  late final GeneratedColumn<bool> enabledCookieJar = GeneratedColumn<bool>(
    'enabledCookieJar',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabledCookieJar" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _lastUpdateTimeMeta = const VerificationMeta(
    'lastUpdateTime',
  );
  @override
  late final GeneratedColumn<int> lastUpdateTime = GeneratedColumn<int>(
    'lastUpdateTime',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _respondTimeMeta = const VerificationMeta(
    'respondTime',
  );
  @override
  late final GeneratedColumn<int> respondTime = GeneratedColumn<int>(
    'respondTime',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(180000),
  );
  static const VerificationMeta _jsLibMeta = const VerificationMeta('jsLib');
  @override
  late final GeneratedColumn<String> jsLib = GeneratedColumn<String>(
    'jsLib',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _concurrentRateMeta = const VerificationMeta(
    'concurrentRate',
  );
  @override
  late final GeneratedColumn<String> concurrentRate = GeneratedColumn<String>(
    'concurrentRate',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exploreUrlMeta = const VerificationMeta(
    'exploreUrl',
  );
  @override
  late final GeneratedColumn<String> exploreUrl = GeneratedColumn<String>(
    'exploreUrl',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exploreScreenMeta = const VerificationMeta(
    'exploreScreen',
  );
  @override
  late final GeneratedColumn<String> exploreScreen = GeneratedColumn<String>(
    'exploreScreen',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _searchUrlMeta = const VerificationMeta(
    'searchUrl',
  );
  @override
  late final GeneratedColumn<String> searchUrl = GeneratedColumn<String>(
    'searchUrl',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SearchRule?, String> ruleSearch =
      GeneratedColumn<String>(
        'ruleSearch',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<SearchRule?>($BookSourcesTable.$converterruleSearch);
  @override
  late final GeneratedColumnWithTypeConverter<ExploreRule?, String>
  ruleExplore = GeneratedColumn<String>(
    'ruleExplore',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  ).withConverter<ExploreRule?>($BookSourcesTable.$converterruleExplore);
  @override
  late final GeneratedColumnWithTypeConverter<BookInfoRule?, String>
  ruleBookInfo = GeneratedColumn<String>(
    'ruleBookInfo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  ).withConverter<BookInfoRule?>($BookSourcesTable.$converterruleBookInfo);
  @override
  late final GeneratedColumnWithTypeConverter<TocRule?, String> ruleToc =
      GeneratedColumn<String>(
        'ruleToc',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<TocRule?>($BookSourcesTable.$converterruleToc);
  @override
  late final GeneratedColumnWithTypeConverter<ContentRule?, String>
  ruleContent = GeneratedColumn<String>(
    'ruleContent',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  ).withConverter<ContentRule?>($BookSourcesTable.$converterruleContent);
  @override
  late final GeneratedColumnWithTypeConverter<ReviewRule?, String> ruleReview =
      GeneratedColumn<String>(
        'ruleReview',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<ReviewRule?>($BookSourcesTable.$converterruleReview);
  @override
  List<GeneratedColumn> get $columns => [
    bookSourceUrl,
    bookSourceName,
    bookSourceType,
    bookSourceGroup,
    bookSourceComment,
    loginUrl,
    loginUi,
    loginCheckJs,
    coverDecodeJs,
    bookUrlPattern,
    header,
    variableComment,
    customOrder,
    weight,
    enabled,
    enabledExplore,
    enabledCookieJar,
    lastUpdateTime,
    respondTime,
    jsLib,
    concurrentRate,
    exploreUrl,
    exploreScreen,
    searchUrl,
    ruleSearch,
    ruleExplore,
    ruleBookInfo,
    ruleToc,
    ruleContent,
    ruleReview,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'book_sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookSource> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('bookSourceUrl')) {
      context.handle(
        _bookSourceUrlMeta,
        bookSourceUrl.isAcceptableOrUnknown(
          data['bookSourceUrl']!,
          _bookSourceUrlMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_bookSourceUrlMeta);
    }
    if (data.containsKey('bookSourceName')) {
      context.handle(
        _bookSourceNameMeta,
        bookSourceName.isAcceptableOrUnknown(
          data['bookSourceName']!,
          _bookSourceNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_bookSourceNameMeta);
    }
    if (data.containsKey('bookSourceType')) {
      context.handle(
        _bookSourceTypeMeta,
        bookSourceType.isAcceptableOrUnknown(
          data['bookSourceType']!,
          _bookSourceTypeMeta,
        ),
      );
    }
    if (data.containsKey('bookSourceGroup')) {
      context.handle(
        _bookSourceGroupMeta,
        bookSourceGroup.isAcceptableOrUnknown(
          data['bookSourceGroup']!,
          _bookSourceGroupMeta,
        ),
      );
    }
    if (data.containsKey('bookSourceComment')) {
      context.handle(
        _bookSourceCommentMeta,
        bookSourceComment.isAcceptableOrUnknown(
          data['bookSourceComment']!,
          _bookSourceCommentMeta,
        ),
      );
    }
    if (data.containsKey('loginUrl')) {
      context.handle(
        _loginUrlMeta,
        loginUrl.isAcceptableOrUnknown(data['loginUrl']!, _loginUrlMeta),
      );
    }
    if (data.containsKey('loginUi')) {
      context.handle(
        _loginUiMeta,
        loginUi.isAcceptableOrUnknown(data['loginUi']!, _loginUiMeta),
      );
    }
    if (data.containsKey('loginCheckJs')) {
      context.handle(
        _loginCheckJsMeta,
        loginCheckJs.isAcceptableOrUnknown(
          data['loginCheckJs']!,
          _loginCheckJsMeta,
        ),
      );
    }
    if (data.containsKey('coverDecodeJs')) {
      context.handle(
        _coverDecodeJsMeta,
        coverDecodeJs.isAcceptableOrUnknown(
          data['coverDecodeJs']!,
          _coverDecodeJsMeta,
        ),
      );
    }
    if (data.containsKey('bookUrlPattern')) {
      context.handle(
        _bookUrlPatternMeta,
        bookUrlPattern.isAcceptableOrUnknown(
          data['bookUrlPattern']!,
          _bookUrlPatternMeta,
        ),
      );
    }
    if (data.containsKey('header')) {
      context.handle(
        _headerMeta,
        header.isAcceptableOrUnknown(data['header']!, _headerMeta),
      );
    }
    if (data.containsKey('variableComment')) {
      context.handle(
        _variableCommentMeta,
        variableComment.isAcceptableOrUnknown(
          data['variableComment']!,
          _variableCommentMeta,
        ),
      );
    }
    if (data.containsKey('customOrder')) {
      context.handle(
        _customOrderMeta,
        customOrder.isAcceptableOrUnknown(
          data['customOrder']!,
          _customOrderMeta,
        ),
      );
    }
    if (data.containsKey('weight')) {
      context.handle(
        _weightMeta,
        weight.isAcceptableOrUnknown(data['weight']!, _weightMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('enabledExplore')) {
      context.handle(
        _enabledExploreMeta,
        enabledExplore.isAcceptableOrUnknown(
          data['enabledExplore']!,
          _enabledExploreMeta,
        ),
      );
    }
    if (data.containsKey('enabledCookieJar')) {
      context.handle(
        _enabledCookieJarMeta,
        enabledCookieJar.isAcceptableOrUnknown(
          data['enabledCookieJar']!,
          _enabledCookieJarMeta,
        ),
      );
    }
    if (data.containsKey('lastUpdateTime')) {
      context.handle(
        _lastUpdateTimeMeta,
        lastUpdateTime.isAcceptableOrUnknown(
          data['lastUpdateTime']!,
          _lastUpdateTimeMeta,
        ),
      );
    }
    if (data.containsKey('respondTime')) {
      context.handle(
        _respondTimeMeta,
        respondTime.isAcceptableOrUnknown(
          data['respondTime']!,
          _respondTimeMeta,
        ),
      );
    }
    if (data.containsKey('jsLib')) {
      context.handle(
        _jsLibMeta,
        jsLib.isAcceptableOrUnknown(data['jsLib']!, _jsLibMeta),
      );
    }
    if (data.containsKey('concurrentRate')) {
      context.handle(
        _concurrentRateMeta,
        concurrentRate.isAcceptableOrUnknown(
          data['concurrentRate']!,
          _concurrentRateMeta,
        ),
      );
    }
    if (data.containsKey('exploreUrl')) {
      context.handle(
        _exploreUrlMeta,
        exploreUrl.isAcceptableOrUnknown(data['exploreUrl']!, _exploreUrlMeta),
      );
    }
    if (data.containsKey('exploreScreen')) {
      context.handle(
        _exploreScreenMeta,
        exploreScreen.isAcceptableOrUnknown(
          data['exploreScreen']!,
          _exploreScreenMeta,
        ),
      );
    }
    if (data.containsKey('searchUrl')) {
      context.handle(
        _searchUrlMeta,
        searchUrl.isAcceptableOrUnknown(data['searchUrl']!, _searchUrlMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookSourceUrl};
  @override
  BookSource map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookSource(
      bookSourceUrl:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}bookSourceUrl'],
          )!,
      bookSourceName:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}bookSourceName'],
          )!,
      bookSourceGroup: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bookSourceGroup'],
      ),
      bookSourceType:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}bookSourceType'],
          )!,
      bookUrlPattern: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bookUrlPattern'],
      ),
      customOrder:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}customOrder'],
          )!,
      enabled:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}enabled'],
          )!,
      enabledExplore:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}enabledExplore'],
          )!,
      jsLib: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}jsLib'],
      ),
      enabledCookieJar:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}enabledCookieJar'],
          )!,
      concurrentRate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}concurrentRate'],
      ),
      header: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}header'],
      ),
      loginUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}loginUrl'],
      ),
      loginUi: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}loginUi'],
      ),
      loginCheckJs: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}loginCheckJs'],
      ),
      coverDecodeJs: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coverDecodeJs'],
      ),
      bookSourceComment: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bookSourceComment'],
      ),
      variableComment: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variableComment'],
      ),
      lastUpdateTime:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}lastUpdateTime'],
          )!,
      respondTime:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}respondTime'],
          )!,
      weight:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}weight'],
          )!,
      exploreUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exploreUrl'],
      ),
      exploreScreen: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exploreScreen'],
      ),
      ruleExplore: $BookSourcesTable.$converterruleExplore.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}ruleExplore'],
        ),
      ),
      searchUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}searchUrl'],
      ),
      ruleSearch: $BookSourcesTable.$converterruleSearch.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}ruleSearch'],
        ),
      ),
      ruleBookInfo: $BookSourcesTable.$converterruleBookInfo.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}ruleBookInfo'],
        ),
      ),
      ruleToc: $BookSourcesTable.$converterruleToc.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}ruleToc'],
        ),
      ),
      ruleContent: $BookSourcesTable.$converterruleContent.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}ruleContent'],
        ),
      ),
      ruleReview: $BookSourcesTable.$converterruleReview.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}ruleReview'],
        ),
      ),
    );
  }

  @override
  $BookSourcesTable createAlias(String alias) {
    return $BookSourcesTable(attachedDatabase, alias);
  }

  static TypeConverter<SearchRule?, String?> $converterruleSearch =
      const SearchRuleConverter();
  static TypeConverter<ExploreRule?, String?> $converterruleExplore =
      const ExploreRuleConverter();
  static TypeConverter<BookInfoRule?, String?> $converterruleBookInfo =
      const BookInfoRuleConverter();
  static TypeConverter<TocRule?, String?> $converterruleToc =
      const TocRuleConverter();
  static TypeConverter<ContentRule?, String?> $converterruleContent =
      const ContentRuleConverter();
  static TypeConverter<ReviewRule?, String?> $converterruleReview =
      const ReviewRuleConverter();
}

class BookSourcesCompanion extends UpdateCompanion<BookSource> {
  final Value<String> bookSourceUrl;
  final Value<String> bookSourceName;
  final Value<int> bookSourceType;
  final Value<String?> bookSourceGroup;
  final Value<String?> bookSourceComment;
  final Value<String?> loginUrl;
  final Value<String?> loginUi;
  final Value<String?> loginCheckJs;
  final Value<String?> coverDecodeJs;
  final Value<String?> bookUrlPattern;
  final Value<String?> header;
  final Value<String?> variableComment;
  final Value<int> customOrder;
  final Value<int> weight;
  final Value<bool> enabled;
  final Value<bool> enabledExplore;
  final Value<bool> enabledCookieJar;
  final Value<int> lastUpdateTime;
  final Value<int> respondTime;
  final Value<String?> jsLib;
  final Value<String?> concurrentRate;
  final Value<String?> exploreUrl;
  final Value<String?> exploreScreen;
  final Value<String?> searchUrl;
  final Value<SearchRule?> ruleSearch;
  final Value<ExploreRule?> ruleExplore;
  final Value<BookInfoRule?> ruleBookInfo;
  final Value<TocRule?> ruleToc;
  final Value<ContentRule?> ruleContent;
  final Value<ReviewRule?> ruleReview;
  final Value<int> rowid;
  const BookSourcesCompanion({
    this.bookSourceUrl = const Value.absent(),
    this.bookSourceName = const Value.absent(),
    this.bookSourceType = const Value.absent(),
    this.bookSourceGroup = const Value.absent(),
    this.bookSourceComment = const Value.absent(),
    this.loginUrl = const Value.absent(),
    this.loginUi = const Value.absent(),
    this.loginCheckJs = const Value.absent(),
    this.coverDecodeJs = const Value.absent(),
    this.bookUrlPattern = const Value.absent(),
    this.header = const Value.absent(),
    this.variableComment = const Value.absent(),
    this.customOrder = const Value.absent(),
    this.weight = const Value.absent(),
    this.enabled = const Value.absent(),
    this.enabledExplore = const Value.absent(),
    this.enabledCookieJar = const Value.absent(),
    this.lastUpdateTime = const Value.absent(),
    this.respondTime = const Value.absent(),
    this.jsLib = const Value.absent(),
    this.concurrentRate = const Value.absent(),
    this.exploreUrl = const Value.absent(),
    this.exploreScreen = const Value.absent(),
    this.searchUrl = const Value.absent(),
    this.ruleSearch = const Value.absent(),
    this.ruleExplore = const Value.absent(),
    this.ruleBookInfo = const Value.absent(),
    this.ruleToc = const Value.absent(),
    this.ruleContent = const Value.absent(),
    this.ruleReview = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookSourcesCompanion.insert({
    required String bookSourceUrl,
    required String bookSourceName,
    this.bookSourceType = const Value.absent(),
    this.bookSourceGroup = const Value.absent(),
    this.bookSourceComment = const Value.absent(),
    this.loginUrl = const Value.absent(),
    this.loginUi = const Value.absent(),
    this.loginCheckJs = const Value.absent(),
    this.coverDecodeJs = const Value.absent(),
    this.bookUrlPattern = const Value.absent(),
    this.header = const Value.absent(),
    this.variableComment = const Value.absent(),
    this.customOrder = const Value.absent(),
    this.weight = const Value.absent(),
    this.enabled = const Value.absent(),
    this.enabledExplore = const Value.absent(),
    this.enabledCookieJar = const Value.absent(),
    this.lastUpdateTime = const Value.absent(),
    this.respondTime = const Value.absent(),
    this.jsLib = const Value.absent(),
    this.concurrentRate = const Value.absent(),
    this.exploreUrl = const Value.absent(),
    this.exploreScreen = const Value.absent(),
    this.searchUrl = const Value.absent(),
    this.ruleSearch = const Value.absent(),
    this.ruleExplore = const Value.absent(),
    this.ruleBookInfo = const Value.absent(),
    this.ruleToc = const Value.absent(),
    this.ruleContent = const Value.absent(),
    this.ruleReview = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : bookSourceUrl = Value(bookSourceUrl),
       bookSourceName = Value(bookSourceName);
  static Insertable<BookSource> custom({
    Expression<String>? bookSourceUrl,
    Expression<String>? bookSourceName,
    Expression<int>? bookSourceType,
    Expression<String>? bookSourceGroup,
    Expression<String>? bookSourceComment,
    Expression<String>? loginUrl,
    Expression<String>? loginUi,
    Expression<String>? loginCheckJs,
    Expression<String>? coverDecodeJs,
    Expression<String>? bookUrlPattern,
    Expression<String>? header,
    Expression<String>? variableComment,
    Expression<int>? customOrder,
    Expression<int>? weight,
    Expression<bool>? enabled,
    Expression<bool>? enabledExplore,
    Expression<bool>? enabledCookieJar,
    Expression<int>? lastUpdateTime,
    Expression<int>? respondTime,
    Expression<String>? jsLib,
    Expression<String>? concurrentRate,
    Expression<String>? exploreUrl,
    Expression<String>? exploreScreen,
    Expression<String>? searchUrl,
    Expression<String>? ruleSearch,
    Expression<String>? ruleExplore,
    Expression<String>? ruleBookInfo,
    Expression<String>? ruleToc,
    Expression<String>? ruleContent,
    Expression<String>? ruleReview,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookSourceUrl != null) 'bookSourceUrl': bookSourceUrl,
      if (bookSourceName != null) 'bookSourceName': bookSourceName,
      if (bookSourceType != null) 'bookSourceType': bookSourceType,
      if (bookSourceGroup != null) 'bookSourceGroup': bookSourceGroup,
      if (bookSourceComment != null) 'bookSourceComment': bookSourceComment,
      if (loginUrl != null) 'loginUrl': loginUrl,
      if (loginUi != null) 'loginUi': loginUi,
      if (loginCheckJs != null) 'loginCheckJs': loginCheckJs,
      if (coverDecodeJs != null) 'coverDecodeJs': coverDecodeJs,
      if (bookUrlPattern != null) 'bookUrlPattern': bookUrlPattern,
      if (header != null) 'header': header,
      if (variableComment != null) 'variableComment': variableComment,
      if (customOrder != null) 'customOrder': customOrder,
      if (weight != null) 'weight': weight,
      if (enabled != null) 'enabled': enabled,
      if (enabledExplore != null) 'enabledExplore': enabledExplore,
      if (enabledCookieJar != null) 'enabledCookieJar': enabledCookieJar,
      if (lastUpdateTime != null) 'lastUpdateTime': lastUpdateTime,
      if (respondTime != null) 'respondTime': respondTime,
      if (jsLib != null) 'jsLib': jsLib,
      if (concurrentRate != null) 'concurrentRate': concurrentRate,
      if (exploreUrl != null) 'exploreUrl': exploreUrl,
      if (exploreScreen != null) 'exploreScreen': exploreScreen,
      if (searchUrl != null) 'searchUrl': searchUrl,
      if (ruleSearch != null) 'ruleSearch': ruleSearch,
      if (ruleExplore != null) 'ruleExplore': ruleExplore,
      if (ruleBookInfo != null) 'ruleBookInfo': ruleBookInfo,
      if (ruleToc != null) 'ruleToc': ruleToc,
      if (ruleContent != null) 'ruleContent': ruleContent,
      if (ruleReview != null) 'ruleReview': ruleReview,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookSourcesCompanion copyWith({
    Value<String>? bookSourceUrl,
    Value<String>? bookSourceName,
    Value<int>? bookSourceType,
    Value<String?>? bookSourceGroup,
    Value<String?>? bookSourceComment,
    Value<String?>? loginUrl,
    Value<String?>? loginUi,
    Value<String?>? loginCheckJs,
    Value<String?>? coverDecodeJs,
    Value<String?>? bookUrlPattern,
    Value<String?>? header,
    Value<String?>? variableComment,
    Value<int>? customOrder,
    Value<int>? weight,
    Value<bool>? enabled,
    Value<bool>? enabledExplore,
    Value<bool>? enabledCookieJar,
    Value<int>? lastUpdateTime,
    Value<int>? respondTime,
    Value<String?>? jsLib,
    Value<String?>? concurrentRate,
    Value<String?>? exploreUrl,
    Value<String?>? exploreScreen,
    Value<String?>? searchUrl,
    Value<SearchRule?>? ruleSearch,
    Value<ExploreRule?>? ruleExplore,
    Value<BookInfoRule?>? ruleBookInfo,
    Value<TocRule?>? ruleToc,
    Value<ContentRule?>? ruleContent,
    Value<ReviewRule?>? ruleReview,
    Value<int>? rowid,
  }) {
    return BookSourcesCompanion(
      bookSourceUrl: bookSourceUrl ?? this.bookSourceUrl,
      bookSourceName: bookSourceName ?? this.bookSourceName,
      bookSourceType: bookSourceType ?? this.bookSourceType,
      bookSourceGroup: bookSourceGroup ?? this.bookSourceGroup,
      bookSourceComment: bookSourceComment ?? this.bookSourceComment,
      loginUrl: loginUrl ?? this.loginUrl,
      loginUi: loginUi ?? this.loginUi,
      loginCheckJs: loginCheckJs ?? this.loginCheckJs,
      coverDecodeJs: coverDecodeJs ?? this.coverDecodeJs,
      bookUrlPattern: bookUrlPattern ?? this.bookUrlPattern,
      header: header ?? this.header,
      variableComment: variableComment ?? this.variableComment,
      customOrder: customOrder ?? this.customOrder,
      weight: weight ?? this.weight,
      enabled: enabled ?? this.enabled,
      enabledExplore: enabledExplore ?? this.enabledExplore,
      enabledCookieJar: enabledCookieJar ?? this.enabledCookieJar,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      respondTime: respondTime ?? this.respondTime,
      jsLib: jsLib ?? this.jsLib,
      concurrentRate: concurrentRate ?? this.concurrentRate,
      exploreUrl: exploreUrl ?? this.exploreUrl,
      exploreScreen: exploreScreen ?? this.exploreScreen,
      searchUrl: searchUrl ?? this.searchUrl,
      ruleSearch: ruleSearch ?? this.ruleSearch,
      ruleExplore: ruleExplore ?? this.ruleExplore,
      ruleBookInfo: ruleBookInfo ?? this.ruleBookInfo,
      ruleToc: ruleToc ?? this.ruleToc,
      ruleContent: ruleContent ?? this.ruleContent,
      ruleReview: ruleReview ?? this.ruleReview,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookSourceUrl.present) {
      map['bookSourceUrl'] = Variable<String>(bookSourceUrl.value);
    }
    if (bookSourceName.present) {
      map['bookSourceName'] = Variable<String>(bookSourceName.value);
    }
    if (bookSourceType.present) {
      map['bookSourceType'] = Variable<int>(bookSourceType.value);
    }
    if (bookSourceGroup.present) {
      map['bookSourceGroup'] = Variable<String>(bookSourceGroup.value);
    }
    if (bookSourceComment.present) {
      map['bookSourceComment'] = Variable<String>(bookSourceComment.value);
    }
    if (loginUrl.present) {
      map['loginUrl'] = Variable<String>(loginUrl.value);
    }
    if (loginUi.present) {
      map['loginUi'] = Variable<String>(loginUi.value);
    }
    if (loginCheckJs.present) {
      map['loginCheckJs'] = Variable<String>(loginCheckJs.value);
    }
    if (coverDecodeJs.present) {
      map['coverDecodeJs'] = Variable<String>(coverDecodeJs.value);
    }
    if (bookUrlPattern.present) {
      map['bookUrlPattern'] = Variable<String>(bookUrlPattern.value);
    }
    if (header.present) {
      map['header'] = Variable<String>(header.value);
    }
    if (variableComment.present) {
      map['variableComment'] = Variable<String>(variableComment.value);
    }
    if (customOrder.present) {
      map['customOrder'] = Variable<int>(customOrder.value);
    }
    if (weight.present) {
      map['weight'] = Variable<int>(weight.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (enabledExplore.present) {
      map['enabledExplore'] = Variable<bool>(enabledExplore.value);
    }
    if (enabledCookieJar.present) {
      map['enabledCookieJar'] = Variable<bool>(enabledCookieJar.value);
    }
    if (lastUpdateTime.present) {
      map['lastUpdateTime'] = Variable<int>(lastUpdateTime.value);
    }
    if (respondTime.present) {
      map['respondTime'] = Variable<int>(respondTime.value);
    }
    if (jsLib.present) {
      map['jsLib'] = Variable<String>(jsLib.value);
    }
    if (concurrentRate.present) {
      map['concurrentRate'] = Variable<String>(concurrentRate.value);
    }
    if (exploreUrl.present) {
      map['exploreUrl'] = Variable<String>(exploreUrl.value);
    }
    if (exploreScreen.present) {
      map['exploreScreen'] = Variable<String>(exploreScreen.value);
    }
    if (searchUrl.present) {
      map['searchUrl'] = Variable<String>(searchUrl.value);
    }
    if (ruleSearch.present) {
      map['ruleSearch'] = Variable<String>(
        $BookSourcesTable.$converterruleSearch.toSql(ruleSearch.value),
      );
    }
    if (ruleExplore.present) {
      map['ruleExplore'] = Variable<String>(
        $BookSourcesTable.$converterruleExplore.toSql(ruleExplore.value),
      );
    }
    if (ruleBookInfo.present) {
      map['ruleBookInfo'] = Variable<String>(
        $BookSourcesTable.$converterruleBookInfo.toSql(ruleBookInfo.value),
      );
    }
    if (ruleToc.present) {
      map['ruleToc'] = Variable<String>(
        $BookSourcesTable.$converterruleToc.toSql(ruleToc.value),
      );
    }
    if (ruleContent.present) {
      map['ruleContent'] = Variable<String>(
        $BookSourcesTable.$converterruleContent.toSql(ruleContent.value),
      );
    }
    if (ruleReview.present) {
      map['ruleReview'] = Variable<String>(
        $BookSourcesTable.$converterruleReview.toSql(ruleReview.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookSourcesCompanion(')
          ..write('bookSourceUrl: $bookSourceUrl, ')
          ..write('bookSourceName: $bookSourceName, ')
          ..write('bookSourceType: $bookSourceType, ')
          ..write('bookSourceGroup: $bookSourceGroup, ')
          ..write('bookSourceComment: $bookSourceComment, ')
          ..write('loginUrl: $loginUrl, ')
          ..write('loginUi: $loginUi, ')
          ..write('loginCheckJs: $loginCheckJs, ')
          ..write('coverDecodeJs: $coverDecodeJs, ')
          ..write('bookUrlPattern: $bookUrlPattern, ')
          ..write('header: $header, ')
          ..write('variableComment: $variableComment, ')
          ..write('customOrder: $customOrder, ')
          ..write('weight: $weight, ')
          ..write('enabled: $enabled, ')
          ..write('enabledExplore: $enabledExplore, ')
          ..write('enabledCookieJar: $enabledCookieJar, ')
          ..write('lastUpdateTime: $lastUpdateTime, ')
          ..write('respondTime: $respondTime, ')
          ..write('jsLib: $jsLib, ')
          ..write('concurrentRate: $concurrentRate, ')
          ..write('exploreUrl: $exploreUrl, ')
          ..write('exploreScreen: $exploreScreen, ')
          ..write('searchUrl: $searchUrl, ')
          ..write('ruleSearch: $ruleSearch, ')
          ..write('ruleExplore: $ruleExplore, ')
          ..write('ruleBookInfo: $ruleBookInfo, ')
          ..write('ruleToc: $ruleToc, ')
          ..write('ruleContent: $ruleContent, ')
          ..write('ruleReview: $ruleReview, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class _$BookSourceInsertable implements Insertable<BookSource> {
  BookSource _object;
  _$BookSourceInsertable(this._object);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return BookSourcesCompanion(
      bookSourceUrl: Value(_object.bookSourceUrl),
      bookSourceName: Value(_object.bookSourceName),
      bookSourceType: Value(_object.bookSourceType),
      bookSourceGroup: Value(_object.bookSourceGroup),
      bookSourceComment: Value(_object.bookSourceComment),
      loginUrl: Value(_object.loginUrl),
      loginUi: Value(_object.loginUi),
      loginCheckJs: Value(_object.loginCheckJs),
      coverDecodeJs: Value(_object.coverDecodeJs),
      bookUrlPattern: Value(_object.bookUrlPattern),
      header: Value(_object.header),
      variableComment: Value(_object.variableComment),
      customOrder: Value(_object.customOrder),
      weight: Value(_object.weight),
      enabled: Value(_object.enabled),
      enabledExplore: Value(_object.enabledExplore),
      enabledCookieJar: Value(_object.enabledCookieJar),
      lastUpdateTime: Value(_object.lastUpdateTime),
      respondTime: Value(_object.respondTime),
      jsLib: Value(_object.jsLib),
      concurrentRate: Value(_object.concurrentRate),
      exploreUrl: Value(_object.exploreUrl),
      exploreScreen: Value(_object.exploreScreen),
      searchUrl: Value(_object.searchUrl),
      ruleSearch: Value(_object.ruleSearch),
      ruleExplore: Value(_object.ruleExplore),
      ruleBookInfo: Value(_object.ruleBookInfo),
      ruleToc: Value(_object.ruleToc),
      ruleContent: Value(_object.ruleContent),
      ruleReview: Value(_object.ruleReview),
    ).toColumns(false);
  }
}

extension BookSourceToInsertable on BookSource {
  _$BookSourceInsertable toInsertable() {
    return _$BookSourceInsertable(this);
  }
}

class $BookGroupsTable extends BookGroups
    with TableInfo<$BookGroupsTable, BookGroup> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<int> groupId = GeneratedColumn<int>(
    'groupId',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _groupNameMeta = const VerificationMeta(
    'groupName',
  );
  @override
  late final GeneratedColumn<String> groupName = GeneratedColumn<String>(
    'groupName',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orderMeta = const VerificationMeta('order');
  @override
  late final GeneratedColumn<int> order = GeneratedColumn<int>(
    'order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _showMeta = const VerificationMeta('show');
  @override
  late final GeneratedColumn<bool> show = GeneratedColumn<bool>(
    'show',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("show" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _coverPathMeta = const VerificationMeta(
    'coverPath',
  );
  @override
  late final GeneratedColumn<String> coverPath = GeneratedColumn<String>(
    'coverPath',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _enableRefreshMeta = const VerificationMeta(
    'enableRefresh',
  );
  @override
  late final GeneratedColumn<bool> enableRefresh = GeneratedColumn<bool>(
    'enableRefresh',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enableRefresh" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _bookSortMeta = const VerificationMeta(
    'bookSort',
  );
  @override
  late final GeneratedColumn<int> bookSort = GeneratedColumn<int>(
    'bookSort',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    groupName,
    order,
    show,
    coverPath,
    enableRefresh,
    bookSort,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'book_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookGroup> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('groupId')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['groupId']!, _groupIdMeta),
      );
    }
    if (data.containsKey('groupName')) {
      context.handle(
        _groupNameMeta,
        groupName.isAcceptableOrUnknown(data['groupName']!, _groupNameMeta),
      );
    } else if (isInserting) {
      context.missing(_groupNameMeta);
    }
    if (data.containsKey('order')) {
      context.handle(
        _orderMeta,
        order.isAcceptableOrUnknown(data['order']!, _orderMeta),
      );
    }
    if (data.containsKey('show')) {
      context.handle(
        _showMeta,
        show.isAcceptableOrUnknown(data['show']!, _showMeta),
      );
    }
    if (data.containsKey('coverPath')) {
      context.handle(
        _coverPathMeta,
        coverPath.isAcceptableOrUnknown(data['coverPath']!, _coverPathMeta),
      );
    }
    if (data.containsKey('enableRefresh')) {
      context.handle(
        _enableRefreshMeta,
        enableRefresh.isAcceptableOrUnknown(
          data['enableRefresh']!,
          _enableRefreshMeta,
        ),
      );
    }
    if (data.containsKey('bookSort')) {
      context.handle(
        _bookSortMeta,
        bookSort.isAcceptableOrUnknown(data['bookSort']!, _bookSortMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId};
  @override
  BookGroup map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookGroup(
      groupId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}groupId'],
          )!,
      groupName:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}groupName'],
          )!,
      coverPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coverPath'],
      ),
      order:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}order'],
          )!,
      enableRefresh:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}enableRefresh'],
          )!,
      show:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}show'],
          )!,
      bookSort:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}bookSort'],
          )!,
    );
  }

  @override
  $BookGroupsTable createAlias(String alias) {
    return $BookGroupsTable(attachedDatabase, alias);
  }
}

class BookGroupsCompanion extends UpdateCompanion<BookGroup> {
  final Value<int> groupId;
  final Value<String> groupName;
  final Value<int> order;
  final Value<bool> show;
  final Value<String?> coverPath;
  final Value<bool> enableRefresh;
  final Value<int> bookSort;
  const BookGroupsCompanion({
    this.groupId = const Value.absent(),
    this.groupName = const Value.absent(),
    this.order = const Value.absent(),
    this.show = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.enableRefresh = const Value.absent(),
    this.bookSort = const Value.absent(),
  });
  BookGroupsCompanion.insert({
    this.groupId = const Value.absent(),
    required String groupName,
    this.order = const Value.absent(),
    this.show = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.enableRefresh = const Value.absent(),
    this.bookSort = const Value.absent(),
  }) : groupName = Value(groupName);
  static Insertable<BookGroup> custom({
    Expression<int>? groupId,
    Expression<String>? groupName,
    Expression<int>? order,
    Expression<bool>? show,
    Expression<String>? coverPath,
    Expression<bool>? enableRefresh,
    Expression<int>? bookSort,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'groupId': groupId,
      if (groupName != null) 'groupName': groupName,
      if (order != null) 'order': order,
      if (show != null) 'show': show,
      if (coverPath != null) 'coverPath': coverPath,
      if (enableRefresh != null) 'enableRefresh': enableRefresh,
      if (bookSort != null) 'bookSort': bookSort,
    });
  }

  BookGroupsCompanion copyWith({
    Value<int>? groupId,
    Value<String>? groupName,
    Value<int>? order,
    Value<bool>? show,
    Value<String?>? coverPath,
    Value<bool>? enableRefresh,
    Value<int>? bookSort,
  }) {
    return BookGroupsCompanion(
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      order: order ?? this.order,
      show: show ?? this.show,
      coverPath: coverPath ?? this.coverPath,
      enableRefresh: enableRefresh ?? this.enableRefresh,
      bookSort: bookSort ?? this.bookSort,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['groupId'] = Variable<int>(groupId.value);
    }
    if (groupName.present) {
      map['groupName'] = Variable<String>(groupName.value);
    }
    if (order.present) {
      map['order'] = Variable<int>(order.value);
    }
    if (show.present) {
      map['show'] = Variable<bool>(show.value);
    }
    if (coverPath.present) {
      map['coverPath'] = Variable<String>(coverPath.value);
    }
    if (enableRefresh.present) {
      map['enableRefresh'] = Variable<bool>(enableRefresh.value);
    }
    if (bookSort.present) {
      map['bookSort'] = Variable<int>(bookSort.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookGroupsCompanion(')
          ..write('groupId: $groupId, ')
          ..write('groupName: $groupName, ')
          ..write('order: $order, ')
          ..write('show: $show, ')
          ..write('coverPath: $coverPath, ')
          ..write('enableRefresh: $enableRefresh, ')
          ..write('bookSort: $bookSort')
          ..write(')'))
        .toString();
  }
}

class _$BookGroupInsertable implements Insertable<BookGroup> {
  BookGroup _object;
  _$BookGroupInsertable(this._object);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return BookGroupsCompanion(
      groupId: Value(_object.groupId),
      groupName: Value(_object.groupName),
      order: Value(_object.order),
      show: Value(_object.show),
      coverPath: Value(_object.coverPath),
      enableRefresh: Value(_object.enableRefresh),
      bookSort: Value(_object.bookSort),
    ).toColumns(false);
  }
}

extension BookGroupToInsertable on BookGroup {
  _$BookGroupInsertable toInsertable() {
    return _$BookGroupInsertable(this);
  }
}

class $SearchHistoryTableTable extends SearchHistoryTable
    with TableInfo<$SearchHistoryTableTable, SearchHistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SearchHistoryTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _keywordMeta = const VerificationMeta(
    'keyword',
  );
  @override
  late final GeneratedColumn<String> keyword = GeneratedColumn<String>(
    'keyword',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _searchTimeMeta = const VerificationMeta(
    'searchTime',
  );
  @override
  late final GeneratedColumn<int> searchTime = GeneratedColumn<int>(
    'searchTime',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, keyword, searchTime];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'search_history_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<SearchHistoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('keyword')) {
      context.handle(
        _keywordMeta,
        keyword.isAcceptableOrUnknown(data['keyword']!, _keywordMeta),
      );
    } else if (isInserting) {
      context.missing(_keywordMeta);
    }
    if (data.containsKey('searchTime')) {
      context.handle(
        _searchTimeMeta,
        searchTime.isAcceptableOrUnknown(data['searchTime']!, _searchTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_searchTimeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SearchHistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SearchHistoryRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      keyword:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}keyword'],
          )!,
      searchTime:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}searchTime'],
          )!,
    );
  }

  @override
  $SearchHistoryTableTable createAlias(String alias) {
    return $SearchHistoryTableTable(attachedDatabase, alias);
  }
}

class SearchHistoryRow extends DataClass
    implements Insertable<SearchHistoryRow> {
  final int id;
  final String keyword;
  final int searchTime;
  const SearchHistoryRow({
    required this.id,
    required this.keyword,
    required this.searchTime,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['keyword'] = Variable<String>(keyword);
    map['searchTime'] = Variable<int>(searchTime);
    return map;
  }

  SearchHistoryTableCompanion toCompanion(bool nullToAbsent) {
    return SearchHistoryTableCompanion(
      id: Value(id),
      keyword: Value(keyword),
      searchTime: Value(searchTime),
    );
  }

  factory SearchHistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SearchHistoryRow(
      id: serializer.fromJson<int>(json['id']),
      keyword: serializer.fromJson<String>(json['keyword']),
      searchTime: serializer.fromJson<int>(json['searchTime']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'keyword': serializer.toJson<String>(keyword),
      'searchTime': serializer.toJson<int>(searchTime),
    };
  }

  SearchHistoryRow copyWith({int? id, String? keyword, int? searchTime}) =>
      SearchHistoryRow(
        id: id ?? this.id,
        keyword: keyword ?? this.keyword,
        searchTime: searchTime ?? this.searchTime,
      );
  SearchHistoryRow copyWithCompanion(SearchHistoryTableCompanion data) {
    return SearchHistoryRow(
      id: data.id.present ? data.id.value : this.id,
      keyword: data.keyword.present ? data.keyword.value : this.keyword,
      searchTime:
          data.searchTime.present ? data.searchTime.value : this.searchTime,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SearchHistoryRow(')
          ..write('id: $id, ')
          ..write('keyword: $keyword, ')
          ..write('searchTime: $searchTime')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, keyword, searchTime);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SearchHistoryRow &&
          other.id == this.id &&
          other.keyword == this.keyword &&
          other.searchTime == this.searchTime);
}

class SearchHistoryTableCompanion extends UpdateCompanion<SearchHistoryRow> {
  final Value<int> id;
  final Value<String> keyword;
  final Value<int> searchTime;
  const SearchHistoryTableCompanion({
    this.id = const Value.absent(),
    this.keyword = const Value.absent(),
    this.searchTime = const Value.absent(),
  });
  SearchHistoryTableCompanion.insert({
    this.id = const Value.absent(),
    required String keyword,
    required int searchTime,
  }) : keyword = Value(keyword),
       searchTime = Value(searchTime);
  static Insertable<SearchHistoryRow> custom({
    Expression<int>? id,
    Expression<String>? keyword,
    Expression<int>? searchTime,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (keyword != null) 'keyword': keyword,
      if (searchTime != null) 'searchTime': searchTime,
    });
  }

  SearchHistoryTableCompanion copyWith({
    Value<int>? id,
    Value<String>? keyword,
    Value<int>? searchTime,
  }) {
    return SearchHistoryTableCompanion(
      id: id ?? this.id,
      keyword: keyword ?? this.keyword,
      searchTime: searchTime ?? this.searchTime,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (keyword.present) {
      map['keyword'] = Variable<String>(keyword.value);
    }
    if (searchTime.present) {
      map['searchTime'] = Variable<int>(searchTime.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SearchHistoryTableCompanion(')
          ..write('id: $id, ')
          ..write('keyword: $keyword, ')
          ..write('searchTime: $searchTime')
          ..write(')'))
        .toString();
  }
}

class $ReplaceRulesTable extends ReplaceRules
    with TableInfo<$ReplaceRulesTable, ReplaceRule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReplaceRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<String, String> name =
      GeneratedColumn<String>(
        'name',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<String>($ReplaceRulesTable.$convertername);
  static const VerificationMeta _patternMeta = const VerificationMeta(
    'pattern',
  );
  @override
  late final GeneratedColumn<String> pattern = GeneratedColumn<String>(
    'pattern',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<String, String> replacement =
      GeneratedColumn<String>(
        'replacement',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<String>($ReplaceRulesTable.$converterreplacement);
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scopeTitleMeta = const VerificationMeta(
    'scopeTitle',
  );
  @override
  late final GeneratedColumn<bool> scopeTitle = GeneratedColumn<bool>(
    'scopeTitle',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("scopeTitle" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _scopeContentMeta = const VerificationMeta(
    'scopeContent',
  );
  @override
  late final GeneratedColumn<bool> scopeContent = GeneratedColumn<bool>(
    'scopeContent',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("scopeContent" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _excludeScopeMeta = const VerificationMeta(
    'excludeScope',
  );
  @override
  late final GeneratedColumn<String> excludeScope = GeneratedColumn<String>(
    'excludeScope',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isEnabledMeta = const VerificationMeta(
    'isEnabled',
  );
  @override
  late final GeneratedColumn<bool> isEnabled = GeneratedColumn<bool>(
    'isEnabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("isEnabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _isRegexMeta = const VerificationMeta(
    'isRegex',
  );
  @override
  late final GeneratedColumn<bool> isRegex = GeneratedColumn<bool>(
    'isRegex',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("isRegex" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _timeoutMillisecondMeta =
      const VerificationMeta('timeoutMillisecond');
  @override
  late final GeneratedColumn<int> timeoutMillisecond = GeneratedColumn<int>(
    'timeoutMillisecond',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(3000),
  );
  static const VerificationMeta _groupMeta = const VerificationMeta('group');
  @override
  late final GeneratedColumn<String> group = GeneratedColumn<String>(
    'group',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _orderMeta = const VerificationMeta('order');
  @override
  late final GeneratedColumn<int> order = GeneratedColumn<int>(
    'order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    pattern,
    replacement,
    scope,
    scopeTitle,
    scopeContent,
    excludeScope,
    isEnabled,
    isRegex,
    timeoutMillisecond,
    group,
    order,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'replace_rules';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReplaceRule> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('pattern')) {
      context.handle(
        _patternMeta,
        pattern.isAcceptableOrUnknown(data['pattern']!, _patternMeta),
      );
    } else if (isInserting) {
      context.missing(_patternMeta);
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    if (data.containsKey('scopeTitle')) {
      context.handle(
        _scopeTitleMeta,
        scopeTitle.isAcceptableOrUnknown(data['scopeTitle']!, _scopeTitleMeta),
      );
    }
    if (data.containsKey('scopeContent')) {
      context.handle(
        _scopeContentMeta,
        scopeContent.isAcceptableOrUnknown(
          data['scopeContent']!,
          _scopeContentMeta,
        ),
      );
    }
    if (data.containsKey('excludeScope')) {
      context.handle(
        _excludeScopeMeta,
        excludeScope.isAcceptableOrUnknown(
          data['excludeScope']!,
          _excludeScopeMeta,
        ),
      );
    }
    if (data.containsKey('isEnabled')) {
      context.handle(
        _isEnabledMeta,
        isEnabled.isAcceptableOrUnknown(data['isEnabled']!, _isEnabledMeta),
      );
    }
    if (data.containsKey('isRegex')) {
      context.handle(
        _isRegexMeta,
        isRegex.isAcceptableOrUnknown(data['isRegex']!, _isRegexMeta),
      );
    }
    if (data.containsKey('timeoutMillisecond')) {
      context.handle(
        _timeoutMillisecondMeta,
        timeoutMillisecond.isAcceptableOrUnknown(
          data['timeoutMillisecond']!,
          _timeoutMillisecondMeta,
        ),
      );
    }
    if (data.containsKey('group')) {
      context.handle(
        _groupMeta,
        group.isAcceptableOrUnknown(data['group']!, _groupMeta),
      );
    }
    if (data.containsKey('order')) {
      context.handle(
        _orderMeta,
        order.isAcceptableOrUnknown(data['order']!, _orderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReplaceRule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReplaceRule(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      name: $ReplaceRulesTable.$convertername.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}name'],
        ),
      ),
      group: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group'],
      ),
      pattern:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}pattern'],
          )!,
      replacement: $ReplaceRulesTable.$converterreplacement.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}replacement'],
        ),
      ),
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      ),
      scopeTitle:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}scopeTitle'],
          )!,
      scopeContent:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}scopeContent'],
          )!,
      excludeScope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}excludeScope'],
      ),
      isEnabled:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}isEnabled'],
          )!,
      isRegex:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}isRegex'],
          )!,
      timeoutMillisecond:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}timeoutMillisecond'],
          )!,
      order:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}order'],
          )!,
    );
  }

  @override
  $ReplaceRulesTable createAlias(String alias) {
    return $ReplaceRulesTable(attachedDatabase, alias);
  }

  static TypeConverter<String, String?> $convertername =
      const EmptyStringConverter();
  static TypeConverter<String, String?> $converterreplacement =
      const EmptyStringConverter();
}

class ReplaceRulesCompanion extends UpdateCompanion<ReplaceRule> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> pattern;
  final Value<String> replacement;
  final Value<String?> scope;
  final Value<bool> scopeTitle;
  final Value<bool> scopeContent;
  final Value<String?> excludeScope;
  final Value<bool> isEnabled;
  final Value<bool> isRegex;
  final Value<int> timeoutMillisecond;
  final Value<String?> group;
  final Value<int> order;
  const ReplaceRulesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.pattern = const Value.absent(),
    this.replacement = const Value.absent(),
    this.scope = const Value.absent(),
    this.scopeTitle = const Value.absent(),
    this.scopeContent = const Value.absent(),
    this.excludeScope = const Value.absent(),
    this.isEnabled = const Value.absent(),
    this.isRegex = const Value.absent(),
    this.timeoutMillisecond = const Value.absent(),
    this.group = const Value.absent(),
    this.order = const Value.absent(),
  });
  ReplaceRulesCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    required String pattern,
    this.replacement = const Value.absent(),
    this.scope = const Value.absent(),
    this.scopeTitle = const Value.absent(),
    this.scopeContent = const Value.absent(),
    this.excludeScope = const Value.absent(),
    this.isEnabled = const Value.absent(),
    this.isRegex = const Value.absent(),
    this.timeoutMillisecond = const Value.absent(),
    this.group = const Value.absent(),
    this.order = const Value.absent(),
  }) : pattern = Value(pattern);
  static Insertable<ReplaceRule> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? pattern,
    Expression<String>? replacement,
    Expression<String>? scope,
    Expression<bool>? scopeTitle,
    Expression<bool>? scopeContent,
    Expression<String>? excludeScope,
    Expression<bool>? isEnabled,
    Expression<bool>? isRegex,
    Expression<int>? timeoutMillisecond,
    Expression<String>? group,
    Expression<int>? order,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (pattern != null) 'pattern': pattern,
      if (replacement != null) 'replacement': replacement,
      if (scope != null) 'scope': scope,
      if (scopeTitle != null) 'scopeTitle': scopeTitle,
      if (scopeContent != null) 'scopeContent': scopeContent,
      if (excludeScope != null) 'excludeScope': excludeScope,
      if (isEnabled != null) 'isEnabled': isEnabled,
      if (isRegex != null) 'isRegex': isRegex,
      if (timeoutMillisecond != null) 'timeoutMillisecond': timeoutMillisecond,
      if (group != null) 'group': group,
      if (order != null) 'order': order,
    });
  }

  ReplaceRulesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? pattern,
    Value<String>? replacement,
    Value<String?>? scope,
    Value<bool>? scopeTitle,
    Value<bool>? scopeContent,
    Value<String?>? excludeScope,
    Value<bool>? isEnabled,
    Value<bool>? isRegex,
    Value<int>? timeoutMillisecond,
    Value<String?>? group,
    Value<int>? order,
  }) {
    return ReplaceRulesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      pattern: pattern ?? this.pattern,
      replacement: replacement ?? this.replacement,
      scope: scope ?? this.scope,
      scopeTitle: scopeTitle ?? this.scopeTitle,
      scopeContent: scopeContent ?? this.scopeContent,
      excludeScope: excludeScope ?? this.excludeScope,
      isEnabled: isEnabled ?? this.isEnabled,
      isRegex: isRegex ?? this.isRegex,
      timeoutMillisecond: timeoutMillisecond ?? this.timeoutMillisecond,
      group: group ?? this.group,
      order: order ?? this.order,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(
        $ReplaceRulesTable.$convertername.toSql(name.value),
      );
    }
    if (pattern.present) {
      map['pattern'] = Variable<String>(pattern.value);
    }
    if (replacement.present) {
      map['replacement'] = Variable<String>(
        $ReplaceRulesTable.$converterreplacement.toSql(replacement.value),
      );
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (scopeTitle.present) {
      map['scopeTitle'] = Variable<bool>(scopeTitle.value);
    }
    if (scopeContent.present) {
      map['scopeContent'] = Variable<bool>(scopeContent.value);
    }
    if (excludeScope.present) {
      map['excludeScope'] = Variable<String>(excludeScope.value);
    }
    if (isEnabled.present) {
      map['isEnabled'] = Variable<bool>(isEnabled.value);
    }
    if (isRegex.present) {
      map['isRegex'] = Variable<bool>(isRegex.value);
    }
    if (timeoutMillisecond.present) {
      map['timeoutMillisecond'] = Variable<int>(timeoutMillisecond.value);
    }
    if (group.present) {
      map['group'] = Variable<String>(group.value);
    }
    if (order.present) {
      map['order'] = Variable<int>(order.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReplaceRulesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('pattern: $pattern, ')
          ..write('replacement: $replacement, ')
          ..write('scope: $scope, ')
          ..write('scopeTitle: $scopeTitle, ')
          ..write('scopeContent: $scopeContent, ')
          ..write('excludeScope: $excludeScope, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('isRegex: $isRegex, ')
          ..write('timeoutMillisecond: $timeoutMillisecond, ')
          ..write('group: $group, ')
          ..write('order: $order')
          ..write(')'))
        .toString();
  }
}

class _$ReplaceRuleInsertable implements Insertable<ReplaceRule> {
  ReplaceRule _object;
  _$ReplaceRuleInsertable(this._object);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return ReplaceRulesCompanion(
      id: Value(_object.id),
      name: Value(_object.name),
      pattern: Value(_object.pattern),
      replacement: Value(_object.replacement),
      scope: Value(_object.scope),
      scopeTitle: Value(_object.scopeTitle),
      scopeContent: Value(_object.scopeContent),
      excludeScope: Value(_object.excludeScope),
      isEnabled: Value(_object.isEnabled),
      isRegex: Value(_object.isRegex),
      timeoutMillisecond: Value(_object.timeoutMillisecond),
      group: Value(_object.group),
      order: Value(_object.order),
    ).toColumns(false);
  }
}

extension ReplaceRuleToInsertable on ReplaceRule {
  _$ReplaceRuleInsertable toInsertable() {
    return _$ReplaceRuleInsertable(this);
  }
}

class $BookmarksTable extends Bookmarks
    with TableInfo<$BookmarksTable, Bookmark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookmarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _timeMeta = const VerificationMeta('time');
  @override
  late final GeneratedColumn<int> time = GeneratedColumn<int>(
    'time',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookNameMeta = const VerificationMeta(
    'bookName',
  );
  @override
  late final GeneratedColumn<String> bookName = GeneratedColumn<String>(
    'bookName',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<String, String> bookAuthor =
      GeneratedColumn<String>(
        'bookAuthor',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<String>($BookmarksTable.$converterbookAuthor);
  static const VerificationMeta _chapterIndexMeta = const VerificationMeta(
    'chapterIndex',
  );
  @override
  late final GeneratedColumn<int> chapterIndex = GeneratedColumn<int>(
    'chapterIndex',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _chapterPosMeta = const VerificationMeta(
    'chapterPos',
  );
  @override
  late final GeneratedColumn<int> chapterPos = GeneratedColumn<int>(
    'chapterPos',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<String, String> chapterName =
      GeneratedColumn<String>(
        'chapterName',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<String>($BookmarksTable.$converterchapterName);
  static const VerificationMeta _bookUrlMeta = const VerificationMeta(
    'bookUrl',
  );
  @override
  late final GeneratedColumn<String> bookUrl = GeneratedColumn<String>(
    'bookUrl',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<String, String> bookText =
      GeneratedColumn<String>(
        'bookText',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<String>($BookmarksTable.$converterbookText);
  @override
  late final GeneratedColumnWithTypeConverter<String, String> content =
      GeneratedColumn<String>(
        'content',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<String>($BookmarksTable.$convertercontent);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    time,
    bookName,
    bookAuthor,
    chapterIndex,
    chapterPos,
    chapterName,
    bookUrl,
    bookText,
    content,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bookmarks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Bookmark> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('time')) {
      context.handle(
        _timeMeta,
        time.isAcceptableOrUnknown(data['time']!, _timeMeta),
      );
    } else if (isInserting) {
      context.missing(_timeMeta);
    }
    if (data.containsKey('bookName')) {
      context.handle(
        _bookNameMeta,
        bookName.isAcceptableOrUnknown(data['bookName']!, _bookNameMeta),
      );
    } else if (isInserting) {
      context.missing(_bookNameMeta);
    }
    if (data.containsKey('chapterIndex')) {
      context.handle(
        _chapterIndexMeta,
        chapterIndex.isAcceptableOrUnknown(
          data['chapterIndex']!,
          _chapterIndexMeta,
        ),
      );
    }
    if (data.containsKey('chapterPos')) {
      context.handle(
        _chapterPosMeta,
        chapterPos.isAcceptableOrUnknown(data['chapterPos']!, _chapterPosMeta),
      );
    }
    if (data.containsKey('bookUrl')) {
      context.handle(
        _bookUrlMeta,
        bookUrl.isAcceptableOrUnknown(data['bookUrl']!, _bookUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_bookUrlMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Bookmark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Bookmark(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      time:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}time'],
          )!,
      bookName:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}bookName'],
          )!,
      bookAuthor: $BookmarksTable.$converterbookAuthor.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}bookAuthor'],
        ),
      ),
      chapterIndex:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}chapterIndex'],
          )!,
      chapterPos:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}chapterPos'],
          )!,
      chapterName: $BookmarksTable.$converterchapterName.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}chapterName'],
        ),
      ),
      bookUrl:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}bookUrl'],
          )!,
      bookText: $BookmarksTable.$converterbookText.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}bookText'],
        ),
      ),
      content: $BookmarksTable.$convertercontent.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}content'],
        ),
      ),
    );
  }

  @override
  $BookmarksTable createAlias(String alias) {
    return $BookmarksTable(attachedDatabase, alias);
  }

  static TypeConverter<String, String?> $converterbookAuthor =
      const EmptyStringConverter();
  static TypeConverter<String, String?> $converterchapterName =
      const EmptyStringConverter();
  static TypeConverter<String, String?> $converterbookText =
      const EmptyStringConverter();
  static TypeConverter<String, String?> $convertercontent =
      const EmptyStringConverter();
}

class BookmarksCompanion extends UpdateCompanion<Bookmark> {
  final Value<int> id;
  final Value<int> time;
  final Value<String> bookName;
  final Value<String> bookAuthor;
  final Value<int> chapterIndex;
  final Value<int> chapterPos;
  final Value<String> chapterName;
  final Value<String> bookUrl;
  final Value<String> bookText;
  final Value<String> content;
  const BookmarksCompanion({
    this.id = const Value.absent(),
    this.time = const Value.absent(),
    this.bookName = const Value.absent(),
    this.bookAuthor = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.chapterPos = const Value.absent(),
    this.chapterName = const Value.absent(),
    this.bookUrl = const Value.absent(),
    this.bookText = const Value.absent(),
    this.content = const Value.absent(),
  });
  BookmarksCompanion.insert({
    this.id = const Value.absent(),
    required int time,
    required String bookName,
    this.bookAuthor = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.chapterPos = const Value.absent(),
    this.chapterName = const Value.absent(),
    required String bookUrl,
    this.bookText = const Value.absent(),
    this.content = const Value.absent(),
  }) : time = Value(time),
       bookName = Value(bookName),
       bookUrl = Value(bookUrl);
  static Insertable<Bookmark> custom({
    Expression<int>? id,
    Expression<int>? time,
    Expression<String>? bookName,
    Expression<String>? bookAuthor,
    Expression<int>? chapterIndex,
    Expression<int>? chapterPos,
    Expression<String>? chapterName,
    Expression<String>? bookUrl,
    Expression<String>? bookText,
    Expression<String>? content,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (time != null) 'time': time,
      if (bookName != null) 'bookName': bookName,
      if (bookAuthor != null) 'bookAuthor': bookAuthor,
      if (chapterIndex != null) 'chapterIndex': chapterIndex,
      if (chapterPos != null) 'chapterPos': chapterPos,
      if (chapterName != null) 'chapterName': chapterName,
      if (bookUrl != null) 'bookUrl': bookUrl,
      if (bookText != null) 'bookText': bookText,
      if (content != null) 'content': content,
    });
  }

  BookmarksCompanion copyWith({
    Value<int>? id,
    Value<int>? time,
    Value<String>? bookName,
    Value<String>? bookAuthor,
    Value<int>? chapterIndex,
    Value<int>? chapterPos,
    Value<String>? chapterName,
    Value<String>? bookUrl,
    Value<String>? bookText,
    Value<String>? content,
  }) {
    return BookmarksCompanion(
      id: id ?? this.id,
      time: time ?? this.time,
      bookName: bookName ?? this.bookName,
      bookAuthor: bookAuthor ?? this.bookAuthor,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      chapterPos: chapterPos ?? this.chapterPos,
      chapterName: chapterName ?? this.chapterName,
      bookUrl: bookUrl ?? this.bookUrl,
      bookText: bookText ?? this.bookText,
      content: content ?? this.content,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (time.present) {
      map['time'] = Variable<int>(time.value);
    }
    if (bookName.present) {
      map['bookName'] = Variable<String>(bookName.value);
    }
    if (bookAuthor.present) {
      map['bookAuthor'] = Variable<String>(
        $BookmarksTable.$converterbookAuthor.toSql(bookAuthor.value),
      );
    }
    if (chapterIndex.present) {
      map['chapterIndex'] = Variable<int>(chapterIndex.value);
    }
    if (chapterPos.present) {
      map['chapterPos'] = Variable<int>(chapterPos.value);
    }
    if (chapterName.present) {
      map['chapterName'] = Variable<String>(
        $BookmarksTable.$converterchapterName.toSql(chapterName.value),
      );
    }
    if (bookUrl.present) {
      map['bookUrl'] = Variable<String>(bookUrl.value);
    }
    if (bookText.present) {
      map['bookText'] = Variable<String>(
        $BookmarksTable.$converterbookText.toSql(bookText.value),
      );
    }
    if (content.present) {
      map['content'] = Variable<String>(
        $BookmarksTable.$convertercontent.toSql(content.value),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookmarksCompanion(')
          ..write('id: $id, ')
          ..write('time: $time, ')
          ..write('bookName: $bookName, ')
          ..write('bookAuthor: $bookAuthor, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('chapterPos: $chapterPos, ')
          ..write('chapterName: $chapterName, ')
          ..write('bookUrl: $bookUrl, ')
          ..write('bookText: $bookText, ')
          ..write('content: $content')
          ..write(')'))
        .toString();
  }
}

class _$BookmarkInsertable implements Insertable<Bookmark> {
  Bookmark _object;
  _$BookmarkInsertable(this._object);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return BookmarksCompanion(
      id: Value(_object.id),
      time: Value(_object.time),
      bookName: Value(_object.bookName),
      bookAuthor: Value(_object.bookAuthor),
      chapterIndex: Value(_object.chapterIndex),
      chapterPos: Value(_object.chapterPos),
      chapterName: Value(_object.chapterName),
      bookUrl: Value(_object.bookUrl),
      bookText: Value(_object.bookText),
      content: Value(_object.content),
    ).toColumns(false);
  }
}

extension BookmarkToInsertable on Bookmark {
  _$BookmarkInsertable toInsertable() {
    return _$BookmarkInsertable(this);
  }
}

class $CookiesTable extends Cookies with TableInfo<$CookiesTable, Cookie> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CookiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cookieMeta = const VerificationMeta('cookie');
  @override
  late final GeneratedColumn<String> cookie = GeneratedColumn<String>(
    'cookie',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [url, cookie];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cookies';
  @override
  VerificationContext validateIntegrity(
    Insertable<Cookie> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('cookie')) {
      context.handle(
        _cookieMeta,
        cookie.isAcceptableOrUnknown(data['cookie']!, _cookieMeta),
      );
    } else if (isInserting) {
      context.missing(_cookieMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {url};
  @override
  Cookie map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Cookie(
      url:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}url'],
          )!,
      cookie:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}cookie'],
          )!,
    );
  }

  @override
  $CookiesTable createAlias(String alias) {
    return $CookiesTable(attachedDatabase, alias);
  }
}

class CookiesCompanion extends UpdateCompanion<Cookie> {
  final Value<String> url;
  final Value<String> cookie;
  final Value<int> rowid;
  const CookiesCompanion({
    this.url = const Value.absent(),
    this.cookie = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CookiesCompanion.insert({
    required String url,
    required String cookie,
    this.rowid = const Value.absent(),
  }) : url = Value(url),
       cookie = Value(cookie);
  static Insertable<Cookie> custom({
    Expression<String>? url,
    Expression<String>? cookie,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (url != null) 'url': url,
      if (cookie != null) 'cookie': cookie,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CookiesCompanion copyWith({
    Value<String>? url,
    Value<String>? cookie,
    Value<int>? rowid,
  }) {
    return CookiesCompanion(
      url: url ?? this.url,
      cookie: cookie ?? this.cookie,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (cookie.present) {
      map['cookie'] = Variable<String>(cookie.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CookiesCompanion(')
          ..write('url: $url, ')
          ..write('cookie: $cookie, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class _$CookieInsertable implements Insertable<Cookie> {
  Cookie _object;
  _$CookieInsertable(this._object);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return CookiesCompanion(
      url: Value(_object.url),
      cookie: Value(_object.cookie),
    ).toColumns(false);
  }
}

extension CookieToInsertable on Cookie {
  _$CookieInsertable toInsertable() {
    return _$CookieInsertable(this);
  }
}

class $DictRulesTable extends DictRules
    with TableInfo<$DictRulesTable, DictRule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DictRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<String, String> urlRule =
      GeneratedColumn<String>(
        'urlRule',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<String>($DictRulesTable.$converterurlRule);
  @override
  late final GeneratedColumnWithTypeConverter<String, String> showRule =
      GeneratedColumn<String>(
        'showRule',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<String>($DictRulesTable.$convertershowRule);
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _sortNumberMeta = const VerificationMeta(
    'sortNumber',
  );
  @override
  late final GeneratedColumn<int> sortNumber = GeneratedColumn<int>(
    'sortNumber',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    urlRule,
    showRule,
    enabled,
    sortNumber,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dict_rules';
  @override
  VerificationContext validateIntegrity(
    Insertable<DictRule> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('sortNumber')) {
      context.handle(
        _sortNumberMeta,
        sortNumber.isAcceptableOrUnknown(data['sortNumber']!, _sortNumberMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DictRule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DictRule(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      urlRule: $DictRulesTable.$converterurlRule.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}urlRule'],
        ),
      ),
      showRule: $DictRulesTable.$convertershowRule.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}showRule'],
        ),
      ),
      enabled:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}enabled'],
          )!,
      sortNumber:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}sortNumber'],
          )!,
    );
  }

  @override
  $DictRulesTable createAlias(String alias) {
    return $DictRulesTable(attachedDatabase, alias);
  }

  static TypeConverter<String, String?> $converterurlRule =
      const EmptyStringConverter();
  static TypeConverter<String, String?> $convertershowRule =
      const EmptyStringConverter();
}

class DictRulesCompanion extends UpdateCompanion<DictRule> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> urlRule;
  final Value<String> showRule;
  final Value<bool> enabled;
  final Value<int> sortNumber;
  const DictRulesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.urlRule = const Value.absent(),
    this.showRule = const Value.absent(),
    this.enabled = const Value.absent(),
    this.sortNumber = const Value.absent(),
  });
  DictRulesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.urlRule = const Value.absent(),
    this.showRule = const Value.absent(),
    this.enabled = const Value.absent(),
    this.sortNumber = const Value.absent(),
  }) : name = Value(name);
  static Insertable<DictRule> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? urlRule,
    Expression<String>? showRule,
    Expression<bool>? enabled,
    Expression<int>? sortNumber,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (urlRule != null) 'urlRule': urlRule,
      if (showRule != null) 'showRule': showRule,
      if (enabled != null) 'enabled': enabled,
      if (sortNumber != null) 'sortNumber': sortNumber,
    });
  }

  DictRulesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? urlRule,
    Value<String>? showRule,
    Value<bool>? enabled,
    Value<int>? sortNumber,
  }) {
    return DictRulesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      urlRule: urlRule ?? this.urlRule,
      showRule: showRule ?? this.showRule,
      enabled: enabled ?? this.enabled,
      sortNumber: sortNumber ?? this.sortNumber,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (urlRule.present) {
      map['urlRule'] = Variable<String>(
        $DictRulesTable.$converterurlRule.toSql(urlRule.value),
      );
    }
    if (showRule.present) {
      map['showRule'] = Variable<String>(
        $DictRulesTable.$convertershowRule.toSql(showRule.value),
      );
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (sortNumber.present) {
      map['sortNumber'] = Variable<int>(sortNumber.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DictRulesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('urlRule: $urlRule, ')
          ..write('showRule: $showRule, ')
          ..write('enabled: $enabled, ')
          ..write('sortNumber: $sortNumber')
          ..write(')'))
        .toString();
  }
}

class _$DictRuleInsertable implements Insertable<DictRule> {
  DictRule _object;
  _$DictRuleInsertable(this._object);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return DictRulesCompanion(
      id: Value(_object.id),
      name: Value(_object.name),
      urlRule: Value(_object.urlRule),
      showRule: Value(_object.showRule),
      enabled: Value(_object.enabled),
      sortNumber: Value(_object.sortNumber),
    ).toColumns(false);
  }
}

extension DictRuleToInsertable on DictRule {
  _$DictRuleInsertable toInsertable() {
    return _$DictRuleInsertable(this);
  }
}

class $HttpTtsTableTable extends HttpTtsTable
    with TableInfo<$HttpTtsTableTable, HttpTTS> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HttpTtsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentTypeMeta = const VerificationMeta(
    'contentType',
  );
  @override
  late final GeneratedColumn<String> contentType = GeneratedColumn<String>(
    'contentType',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _concurrentRateMeta = const VerificationMeta(
    'concurrentRate',
  );
  @override
  late final GeneratedColumn<String> concurrentRate = GeneratedColumn<String>(
    'concurrentRate',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _loginUrlMeta = const VerificationMeta(
    'loginUrl',
  );
  @override
  late final GeneratedColumn<String> loginUrl = GeneratedColumn<String>(
    'loginUrl',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _loginUiMeta = const VerificationMeta(
    'loginUi',
  );
  @override
  late final GeneratedColumn<String> loginUi = GeneratedColumn<String>(
    'loginUi',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _headerMeta = const VerificationMeta('header');
  @override
  late final GeneratedColumn<String> header = GeneratedColumn<String>(
    'header',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _jsLibMeta = const VerificationMeta('jsLib');
  @override
  late final GeneratedColumn<String> jsLib = GeneratedColumn<String>(
    'jsLib',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _enabledCookieJarMeta = const VerificationMeta(
    'enabledCookieJar',
  );
  @override
  late final GeneratedColumn<bool> enabledCookieJar = GeneratedColumn<bool>(
    'enabledCookieJar',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabledCookieJar" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _loginCheckJsMeta = const VerificationMeta(
    'loginCheckJs',
  );
  @override
  late final GeneratedColumn<String> loginCheckJs = GeneratedColumn<String>(
    'loginCheckJs',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastUpdateTimeMeta = const VerificationMeta(
    'lastUpdateTime',
  );
  @override
  late final GeneratedColumn<int> lastUpdateTime = GeneratedColumn<int>(
    'lastUpdateTime',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    url,
    contentType,
    concurrentRate,
    loginUrl,
    loginUi,
    header,
    jsLib,
    enabledCookieJar,
    loginCheckJs,
    lastUpdateTime,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'http_tts_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<HttpTTS> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('contentType')) {
      context.handle(
        _contentTypeMeta,
        contentType.isAcceptableOrUnknown(
          data['contentType']!,
          _contentTypeMeta,
        ),
      );
    }
    if (data.containsKey('concurrentRate')) {
      context.handle(
        _concurrentRateMeta,
        concurrentRate.isAcceptableOrUnknown(
          data['concurrentRate']!,
          _concurrentRateMeta,
        ),
      );
    }
    if (data.containsKey('loginUrl')) {
      context.handle(
        _loginUrlMeta,
        loginUrl.isAcceptableOrUnknown(data['loginUrl']!, _loginUrlMeta),
      );
    }
    if (data.containsKey('loginUi')) {
      context.handle(
        _loginUiMeta,
        loginUi.isAcceptableOrUnknown(data['loginUi']!, _loginUiMeta),
      );
    }
    if (data.containsKey('header')) {
      context.handle(
        _headerMeta,
        header.isAcceptableOrUnknown(data['header']!, _headerMeta),
      );
    }
    if (data.containsKey('jsLib')) {
      context.handle(
        _jsLibMeta,
        jsLib.isAcceptableOrUnknown(data['jsLib']!, _jsLibMeta),
      );
    }
    if (data.containsKey('enabledCookieJar')) {
      context.handle(
        _enabledCookieJarMeta,
        enabledCookieJar.isAcceptableOrUnknown(
          data['enabledCookieJar']!,
          _enabledCookieJarMeta,
        ),
      );
    }
    if (data.containsKey('loginCheckJs')) {
      context.handle(
        _loginCheckJsMeta,
        loginCheckJs.isAcceptableOrUnknown(
          data['loginCheckJs']!,
          _loginCheckJsMeta,
        ),
      );
    }
    if (data.containsKey('lastUpdateTime')) {
      context.handle(
        _lastUpdateTimeMeta,
        lastUpdateTime.isAcceptableOrUnknown(
          data['lastUpdateTime']!,
          _lastUpdateTimeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HttpTTS map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HttpTTS(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      url:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}url'],
          )!,
      contentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contentType'],
      ),
      concurrentRate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}concurrentRate'],
      ),
      loginUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}loginUrl'],
      ),
      loginUi: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}loginUi'],
      ),
      header: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}header'],
      ),
      jsLib: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}jsLib'],
      ),
      enabledCookieJar:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}enabledCookieJar'],
          )!,
      loginCheckJs: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}loginCheckJs'],
      ),
      lastUpdateTime:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}lastUpdateTime'],
          )!,
    );
  }

  @override
  $HttpTtsTableTable createAlias(String alias) {
    return $HttpTtsTableTable(attachedDatabase, alias);
  }
}

class HttpTtsTableCompanion extends UpdateCompanion<HttpTTS> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> url;
  final Value<String?> contentType;
  final Value<String?> concurrentRate;
  final Value<String?> loginUrl;
  final Value<String?> loginUi;
  final Value<String?> header;
  final Value<String?> jsLib;
  final Value<bool> enabledCookieJar;
  final Value<String?> loginCheckJs;
  final Value<int> lastUpdateTime;
  const HttpTtsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.url = const Value.absent(),
    this.contentType = const Value.absent(),
    this.concurrentRate = const Value.absent(),
    this.loginUrl = const Value.absent(),
    this.loginUi = const Value.absent(),
    this.header = const Value.absent(),
    this.jsLib = const Value.absent(),
    this.enabledCookieJar = const Value.absent(),
    this.loginCheckJs = const Value.absent(),
    this.lastUpdateTime = const Value.absent(),
  });
  HttpTtsTableCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String url,
    this.contentType = const Value.absent(),
    this.concurrentRate = const Value.absent(),
    this.loginUrl = const Value.absent(),
    this.loginUi = const Value.absent(),
    this.header = const Value.absent(),
    this.jsLib = const Value.absent(),
    this.enabledCookieJar = const Value.absent(),
    this.loginCheckJs = const Value.absent(),
    this.lastUpdateTime = const Value.absent(),
  }) : name = Value(name),
       url = Value(url);
  static Insertable<HttpTTS> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? url,
    Expression<String>? contentType,
    Expression<String>? concurrentRate,
    Expression<String>? loginUrl,
    Expression<String>? loginUi,
    Expression<String>? header,
    Expression<String>? jsLib,
    Expression<bool>? enabledCookieJar,
    Expression<String>? loginCheckJs,
    Expression<int>? lastUpdateTime,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (url != null) 'url': url,
      if (contentType != null) 'contentType': contentType,
      if (concurrentRate != null) 'concurrentRate': concurrentRate,
      if (loginUrl != null) 'loginUrl': loginUrl,
      if (loginUi != null) 'loginUi': loginUi,
      if (header != null) 'header': header,
      if (jsLib != null) 'jsLib': jsLib,
      if (enabledCookieJar != null) 'enabledCookieJar': enabledCookieJar,
      if (loginCheckJs != null) 'loginCheckJs': loginCheckJs,
      if (lastUpdateTime != null) 'lastUpdateTime': lastUpdateTime,
    });
  }

  HttpTtsTableCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? url,
    Value<String?>? contentType,
    Value<String?>? concurrentRate,
    Value<String?>? loginUrl,
    Value<String?>? loginUi,
    Value<String?>? header,
    Value<String?>? jsLib,
    Value<bool>? enabledCookieJar,
    Value<String?>? loginCheckJs,
    Value<int>? lastUpdateTime,
  }) {
    return HttpTtsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      contentType: contentType ?? this.contentType,
      concurrentRate: concurrentRate ?? this.concurrentRate,
      loginUrl: loginUrl ?? this.loginUrl,
      loginUi: loginUi ?? this.loginUi,
      header: header ?? this.header,
      jsLib: jsLib ?? this.jsLib,
      enabledCookieJar: enabledCookieJar ?? this.enabledCookieJar,
      loginCheckJs: loginCheckJs ?? this.loginCheckJs,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (contentType.present) {
      map['contentType'] = Variable<String>(contentType.value);
    }
    if (concurrentRate.present) {
      map['concurrentRate'] = Variable<String>(concurrentRate.value);
    }
    if (loginUrl.present) {
      map['loginUrl'] = Variable<String>(loginUrl.value);
    }
    if (loginUi.present) {
      map['loginUi'] = Variable<String>(loginUi.value);
    }
    if (header.present) {
      map['header'] = Variable<String>(header.value);
    }
    if (jsLib.present) {
      map['jsLib'] = Variable<String>(jsLib.value);
    }
    if (enabledCookieJar.present) {
      map['enabledCookieJar'] = Variable<bool>(enabledCookieJar.value);
    }
    if (loginCheckJs.present) {
      map['loginCheckJs'] = Variable<String>(loginCheckJs.value);
    }
    if (lastUpdateTime.present) {
      map['lastUpdateTime'] = Variable<int>(lastUpdateTime.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HttpTtsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('url: $url, ')
          ..write('contentType: $contentType, ')
          ..write('concurrentRate: $concurrentRate, ')
          ..write('loginUrl: $loginUrl, ')
          ..write('loginUi: $loginUi, ')
          ..write('header: $header, ')
          ..write('jsLib: $jsLib, ')
          ..write('enabledCookieJar: $enabledCookieJar, ')
          ..write('loginCheckJs: $loginCheckJs, ')
          ..write('lastUpdateTime: $lastUpdateTime')
          ..write(')'))
        .toString();
  }
}

class _$HttpTTSInsertable implements Insertable<HttpTTS> {
  HttpTTS _object;
  _$HttpTTSInsertable(this._object);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return HttpTtsTableCompanion(
      id: Value(_object.id),
      name: Value(_object.name),
      url: Value(_object.url),
      contentType: Value(_object.contentType),
      concurrentRate: Value(_object.concurrentRate),
      loginUrl: Value(_object.loginUrl),
      loginUi: Value(_object.loginUi),
      header: Value(_object.header),
      jsLib: Value(_object.jsLib),
      enabledCookieJar: Value(_object.enabledCookieJar),
      loginCheckJs: Value(_object.loginCheckJs),
      lastUpdateTime: Value(_object.lastUpdateTime),
    ).toColumns(false);
  }
}

extension HttpTTSToInsertable on HttpTTS {
  _$HttpTTSInsertable toInsertable() {
    return _$HttpTTSInsertable(this);
  }
}

class $ReadRecordsTable extends ReadRecords
    with TableInfo<$ReadRecordsTable, ReadRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _bookNameMeta = const VerificationMeta(
    'bookName',
  );
  @override
  late final GeneratedColumn<String> bookName = GeneratedColumn<String>(
    'bookName',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'deviceId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _readTimeMeta = const VerificationMeta(
    'readTime',
  );
  @override
  late final GeneratedColumn<int> readTime = GeneratedColumn<int>(
    'readTime',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastReadMeta = const VerificationMeta(
    'lastRead',
  );
  @override
  late final GeneratedColumn<int> lastRead = GeneratedColumn<int>(
    'lastRead',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookName,
    deviceId,
    readTime,
    lastRead,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'read_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('bookName')) {
      context.handle(
        _bookNameMeta,
        bookName.isAcceptableOrUnknown(data['bookName']!, _bookNameMeta),
      );
    } else if (isInserting) {
      context.missing(_bookNameMeta);
    }
    if (data.containsKey('deviceId')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['deviceId']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('readTime')) {
      context.handle(
        _readTimeMeta,
        readTime.isAcceptableOrUnknown(data['readTime']!, _readTimeMeta),
      );
    }
    if (data.containsKey('lastRead')) {
      context.handle(
        _lastReadMeta,
        lastRead.isAcceptableOrUnknown(data['lastRead']!, _lastReadMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReadRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadRecord(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      deviceId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}deviceId'],
          )!,
      bookName:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}bookName'],
          )!,
      readTime:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}readTime'],
          )!,
      lastRead:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}lastRead'],
          )!,
    );
  }

  @override
  $ReadRecordsTable createAlias(String alias) {
    return $ReadRecordsTable(attachedDatabase, alias);
  }
}

class ReadRecordsCompanion extends UpdateCompanion<ReadRecord> {
  final Value<int> id;
  final Value<String> bookName;
  final Value<String> deviceId;
  final Value<int> readTime;
  final Value<int> lastRead;
  const ReadRecordsCompanion({
    this.id = const Value.absent(),
    this.bookName = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.readTime = const Value.absent(),
    this.lastRead = const Value.absent(),
  });
  ReadRecordsCompanion.insert({
    this.id = const Value.absent(),
    required String bookName,
    required String deviceId,
    this.readTime = const Value.absent(),
    this.lastRead = const Value.absent(),
  }) : bookName = Value(bookName),
       deviceId = Value(deviceId);
  static Insertable<ReadRecord> custom({
    Expression<int>? id,
    Expression<String>? bookName,
    Expression<String>? deviceId,
    Expression<int>? readTime,
    Expression<int>? lastRead,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookName != null) 'bookName': bookName,
      if (deviceId != null) 'deviceId': deviceId,
      if (readTime != null) 'readTime': readTime,
      if (lastRead != null) 'lastRead': lastRead,
    });
  }

  ReadRecordsCompanion copyWith({
    Value<int>? id,
    Value<String>? bookName,
    Value<String>? deviceId,
    Value<int>? readTime,
    Value<int>? lastRead,
  }) {
    return ReadRecordsCompanion(
      id: id ?? this.id,
      bookName: bookName ?? this.bookName,
      deviceId: deviceId ?? this.deviceId,
      readTime: readTime ?? this.readTime,
      lastRead: lastRead ?? this.lastRead,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bookName.present) {
      map['bookName'] = Variable<String>(bookName.value);
    }
    if (deviceId.present) {
      map['deviceId'] = Variable<String>(deviceId.value);
    }
    if (readTime.present) {
      map['readTime'] = Variable<int>(readTime.value);
    }
    if (lastRead.present) {
      map['lastRead'] = Variable<int>(lastRead.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadRecordsCompanion(')
          ..write('id: $id, ')
          ..write('bookName: $bookName, ')
          ..write('deviceId: $deviceId, ')
          ..write('readTime: $readTime, ')
          ..write('lastRead: $lastRead')
          ..write(')'))
        .toString();
  }
}

class _$ReadRecordInsertable implements Insertable<ReadRecord> {
  ReadRecord _object;
  _$ReadRecordInsertable(this._object);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return ReadRecordsCompanion(
      id: Value(_object.id),
      bookName: Value(_object.bookName),
      deviceId: Value(_object.deviceId),
      readTime: Value(_object.readTime),
      lastRead: Value(_object.lastRead),
    ).toColumns(false);
  }
}

extension ReadRecordToInsertable on ReadRecord {
  _$ReadRecordInsertable toInsertable() {
    return _$ReadRecordInsertable(this);
  }
}

class $ServersTable extends Servers with TableInfo<$ServersTable, Server> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ServersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _configMeta = const VerificationMeta('config');
  @override
  late final GeneratedColumn<String> config = GeneratedColumn<String>(
    'config',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortNumberMeta = const VerificationMeta(
    'sortNumber',
  );
  @override
  late final GeneratedColumn<int> sortNumber = GeneratedColumn<int>(
    'sortNumber',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, type, config, sortNumber];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'servers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Server> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('config')) {
      context.handle(
        _configMeta,
        config.isAcceptableOrUnknown(data['config']!, _configMeta),
      );
    }
    if (data.containsKey('sortNumber')) {
      context.handle(
        _sortNumberMeta,
        sortNumber.isAcceptableOrUnknown(data['sortNumber']!, _sortNumberMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Server map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Server(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      type:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}type'],
          )!,
      config: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config'],
      ),
      sortNumber:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}sortNumber'],
          )!,
    );
  }

  @override
  $ServersTable createAlias(String alias) {
    return $ServersTable(attachedDatabase, alias);
  }
}

class ServersCompanion extends UpdateCompanion<Server> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> type;
  final Value<String?> config;
  final Value<int> sortNumber;
  const ServersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.config = const Value.absent(),
    this.sortNumber = const Value.absent(),
  });
  ServersCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String type,
    this.config = const Value.absent(),
    this.sortNumber = const Value.absent(),
  }) : name = Value(name),
       type = Value(type);
  static Insertable<Server> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? config,
    Expression<int>? sortNumber,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (config != null) 'config': config,
      if (sortNumber != null) 'sortNumber': sortNumber,
    });
  }

  ServersCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? type,
    Value<String?>? config,
    Value<int>? sortNumber,
  }) {
    return ServersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      config: config ?? this.config,
      sortNumber: sortNumber ?? this.sortNumber,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (config.present) {
      map['config'] = Variable<String>(config.value);
    }
    if (sortNumber.present) {
      map['sortNumber'] = Variable<int>(sortNumber.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ServersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('config: $config, ')
          ..write('sortNumber: $sortNumber')
          ..write(')'))
        .toString();
  }
}

class _$ServerInsertable implements Insertable<Server> {
  Server _object;
  _$ServerInsertable(this._object);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return ServersCompanion(
      id: Value(_object.id),
      name: Value(_object.name),
      type: Value(_object.type),
      config: Value(_object.config),
      sortNumber: Value(_object.sortNumber),
    ).toColumns(false);
  }
}

extension ServerToInsertable on Server {
  _$ServerInsertable toInsertable() {
    return _$ServerInsertable(this);
  }
}

class $TxtTocRulesTable extends TxtTocRules
    with TableInfo<$TxtTocRulesTable, TxtTocRule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TxtTocRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ruleMeta = const VerificationMeta('rule');
  @override
  late final GeneratedColumn<String> rule = GeneratedColumn<String>(
    'rule',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _exampleMeta = const VerificationMeta(
    'example',
  );
  @override
  late final GeneratedColumn<String> example = GeneratedColumn<String>(
    'example',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serialNumberMeta = const VerificationMeta(
    'serialNumber',
  );
  @override
  late final GeneratedColumn<int> serialNumber = GeneratedColumn<int>(
    'serialNumber',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(-1),
  );
  static const VerificationMeta _enableMeta = const VerificationMeta('enable');
  @override
  late final GeneratedColumn<bool> enable = GeneratedColumn<bool>(
    'enable',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enable" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    rule,
    example,
    serialNumber,
    enable,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'txt_toc_rules';
  @override
  VerificationContext validateIntegrity(
    Insertable<TxtTocRule> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('rule')) {
      context.handle(
        _ruleMeta,
        rule.isAcceptableOrUnknown(data['rule']!, _ruleMeta),
      );
    } else if (isInserting) {
      context.missing(_ruleMeta);
    }
    if (data.containsKey('example')) {
      context.handle(
        _exampleMeta,
        example.isAcceptableOrUnknown(data['example']!, _exampleMeta),
      );
    }
    if (data.containsKey('serialNumber')) {
      context.handle(
        _serialNumberMeta,
        serialNumber.isAcceptableOrUnknown(
          data['serialNumber']!,
          _serialNumberMeta,
        ),
      );
    }
    if (data.containsKey('enable')) {
      context.handle(
        _enableMeta,
        enable.isAcceptableOrUnknown(data['enable']!, _enableMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TxtTocRule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TxtTocRule(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      rule:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}rule'],
          )!,
      example: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}example'],
      ),
      serialNumber:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}serialNumber'],
          )!,
      enable:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}enable'],
          )!,
    );
  }

  @override
  $TxtTocRulesTable createAlias(String alias) {
    return $TxtTocRulesTable(attachedDatabase, alias);
  }
}

class TxtTocRulesCompanion extends UpdateCompanion<TxtTocRule> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> rule;
  final Value<String?> example;
  final Value<int> serialNumber;
  final Value<bool> enable;
  const TxtTocRulesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.rule = const Value.absent(),
    this.example = const Value.absent(),
    this.serialNumber = const Value.absent(),
    this.enable = const Value.absent(),
  });
  TxtTocRulesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String rule,
    this.example = const Value.absent(),
    this.serialNumber = const Value.absent(),
    this.enable = const Value.absent(),
  }) : name = Value(name),
       rule = Value(rule);
  static Insertable<TxtTocRule> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? rule,
    Expression<String>? example,
    Expression<int>? serialNumber,
    Expression<bool>? enable,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (rule != null) 'rule': rule,
      if (example != null) 'example': example,
      if (serialNumber != null) 'serialNumber': serialNumber,
      if (enable != null) 'enable': enable,
    });
  }

  TxtTocRulesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? rule,
    Value<String?>? example,
    Value<int>? serialNumber,
    Value<bool>? enable,
  }) {
    return TxtTocRulesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      rule: rule ?? this.rule,
      example: example ?? this.example,
      serialNumber: serialNumber ?? this.serialNumber,
      enable: enable ?? this.enable,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (rule.present) {
      map['rule'] = Variable<String>(rule.value);
    }
    if (example.present) {
      map['example'] = Variable<String>(example.value);
    }
    if (serialNumber.present) {
      map['serialNumber'] = Variable<int>(serialNumber.value);
    }
    if (enable.present) {
      map['enable'] = Variable<bool>(enable.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TxtTocRulesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('rule: $rule, ')
          ..write('example: $example, ')
          ..write('serialNumber: $serialNumber, ')
          ..write('enable: $enable')
          ..write(')'))
        .toString();
  }
}

class _$TxtTocRuleInsertable implements Insertable<TxtTocRule> {
  TxtTocRule _object;
  _$TxtTocRuleInsertable(this._object);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return TxtTocRulesCompanion(
      id: Value(_object.id),
      name: Value(_object.name),
      rule: Value(_object.rule),
      example: Value(_object.example),
      serialNumber: Value(_object.serialNumber),
      enable: Value(_object.enable),
    ).toColumns(false);
  }
}

extension TxtTocRuleToInsertable on TxtTocRule {
  _$TxtTocRuleInsertable toInsertable() {
    return _$TxtTocRuleInsertable(this);
  }
}

class $CacheTableTable extends CacheTable
    with TableInfo<$CacheTableTable, Cache> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deadlineMeta = const VerificationMeta(
    'deadline',
  );
  @override
  late final GeneratedColumn<int> deadline = GeneratedColumn<int>(
    'deadline',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, deadline];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cache_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<Cache> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    if (data.containsKey('deadline')) {
      context.handle(
        _deadlineMeta,
        deadline.isAcceptableOrUnknown(data['deadline']!, _deadlineMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Cache map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Cache(
      key:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}key'],
          )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      ),
      deadline:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}deadline'],
          )!,
    );
  }

  @override
  $CacheTableTable createAlias(String alias) {
    return $CacheTableTable(attachedDatabase, alias);
  }
}

class CacheTableCompanion extends UpdateCompanion<Cache> {
  final Value<String> key;
  final Value<String?> value;
  final Value<int> deadline;
  final Value<int> rowid;
  const CacheTableCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.deadline = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CacheTableCompanion.insert({
    required String key,
    this.value = const Value.absent(),
    this.deadline = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key);
  static Insertable<Cache> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? deadline,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (deadline != null) 'deadline': deadline,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CacheTableCompanion copyWith({
    Value<String>? key,
    Value<String?>? value,
    Value<int>? deadline,
    Value<int>? rowid,
  }) {
    return CacheTableCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      deadline: deadline ?? this.deadline,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (deadline.present) {
      map['deadline'] = Variable<int>(deadline.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CacheTableCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('deadline: $deadline, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class _$CacheInsertable implements Insertable<Cache> {
  Cache _object;
  _$CacheInsertable(this._object);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return CacheTableCompanion(
      key: Value(_object.key),
      value: Value(_object.value),
      deadline: Value(_object.deadline),
    ).toColumns(false);
  }
}

extension CacheToInsertable on Cache {
  _$CacheInsertable toInsertable() {
    return _$CacheInsertable(this);
  }
}

class $KeyboardAssistsTable extends KeyboardAssists
    with TableInfo<$KeyboardAssistsTable, KeyboardAssist> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KeyboardAssistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<String, String> value =
      GeneratedColumn<String>(
        'value',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<String>($KeyboardAssistsTable.$convertervalue);
  static const VerificationMeta _serialNoMeta = const VerificationMeta(
    'serialNo',
  );
  @override
  late final GeneratedColumn<int> serialNo = GeneratedColumn<int>(
    'serialNo',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [key, type, value, serialNo];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'keyboard_assists';
  @override
  VerificationContext validateIntegrity(
    Insertable<KeyboardAssist> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('serialNo')) {
      context.handle(
        _serialNoMeta,
        serialNo.isAcceptableOrUnknown(data['serialNo']!, _serialNoMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  KeyboardAssist map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KeyboardAssist(
      type:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}type'],
          )!,
      key:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}key'],
          )!,
      value: $KeyboardAssistsTable.$convertervalue.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}value'],
        ),
      ),
      serialNo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}serialNo'],
          )!,
    );
  }

  @override
  $KeyboardAssistsTable createAlias(String alias) {
    return $KeyboardAssistsTable(attachedDatabase, alias);
  }

  static TypeConverter<String, String?> $convertervalue =
      const EmptyStringConverter();
}

class KeyboardAssistsCompanion extends UpdateCompanion<KeyboardAssist> {
  final Value<String> key;
  final Value<int> type;
  final Value<String> value;
  final Value<int> serialNo;
  final Value<int> rowid;
  const KeyboardAssistsCompanion({
    this.key = const Value.absent(),
    this.type = const Value.absent(),
    this.value = const Value.absent(),
    this.serialNo = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KeyboardAssistsCompanion.insert({
    required String key,
    this.type = const Value.absent(),
    this.value = const Value.absent(),
    this.serialNo = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key);
  static Insertable<KeyboardAssist> custom({
    Expression<String>? key,
    Expression<int>? type,
    Expression<String>? value,
    Expression<int>? serialNo,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (type != null) 'type': type,
      if (value != null) 'value': value,
      if (serialNo != null) 'serialNo': serialNo,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KeyboardAssistsCompanion copyWith({
    Value<String>? key,
    Value<int>? type,
    Value<String>? value,
    Value<int>? serialNo,
    Value<int>? rowid,
  }) {
    return KeyboardAssistsCompanion(
      key: key ?? this.key,
      type: type ?? this.type,
      value: value ?? this.value,
      serialNo: serialNo ?? this.serialNo,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(type.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(
        $KeyboardAssistsTable.$convertervalue.toSql(value.value),
      );
    }
    if (serialNo.present) {
      map['serialNo'] = Variable<int>(serialNo.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KeyboardAssistsCompanion(')
          ..write('key: $key, ')
          ..write('type: $type, ')
          ..write('value: $value, ')
          ..write('serialNo: $serialNo, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class _$KeyboardAssistInsertable implements Insertable<KeyboardAssist> {
  KeyboardAssist _object;
  _$KeyboardAssistInsertable(this._object);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return KeyboardAssistsCompanion(
      key: Value(_object.key),
      type: Value(_object.type),
      value: Value(_object.value),
      serialNo: Value(_object.serialNo),
    ).toColumns(false);
  }
}

extension KeyboardAssistToInsertable on KeyboardAssist {
  _$KeyboardAssistInsertable toInsertable() {
    return _$KeyboardAssistInsertable(this);
  }
}

class $RuleSubsTable extends RuleSubs with TableInfo<$RuleSubsTable, RuleSub> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RuleSubsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _orderMeta = const VerificationMeta('order');
  @override
  late final GeneratedColumn<int> order = GeneratedColumn<int>(
    'order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, url, type, enabled, order];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rule_subs';
  @override
  VerificationContext validateIntegrity(
    Insertable<RuleSub> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('order')) {
      context.handle(
        _orderMeta,
        order.isAcceptableOrUnknown(data['order']!, _orderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RuleSub map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RuleSub(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      url:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}url'],
          )!,
      type:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}type'],
          )!,
      enabled:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}enabled'],
          )!,
      order:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}order'],
          )!,
    );
  }

  @override
  $RuleSubsTable createAlias(String alias) {
    return $RuleSubsTable(attachedDatabase, alias);
  }
}

class RuleSubsCompanion extends UpdateCompanion<RuleSub> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> url;
  final Value<int> type;
  final Value<bool> enabled;
  final Value<int> order;
  const RuleSubsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.url = const Value.absent(),
    this.type = const Value.absent(),
    this.enabled = const Value.absent(),
    this.order = const Value.absent(),
  });
  RuleSubsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String url,
    this.type = const Value.absent(),
    this.enabled = const Value.absent(),
    this.order = const Value.absent(),
  }) : name = Value(name),
       url = Value(url);
  static Insertable<RuleSub> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? url,
    Expression<int>? type,
    Expression<bool>? enabled,
    Expression<int>? order,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (url != null) 'url': url,
      if (type != null) 'type': type,
      if (enabled != null) 'enabled': enabled,
      if (order != null) 'order': order,
    });
  }

  RuleSubsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? url,
    Value<int>? type,
    Value<bool>? enabled,
    Value<int>? order,
  }) {
    return RuleSubsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(type.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (order.present) {
      map['order'] = Variable<int>(order.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RuleSubsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('url: $url, ')
          ..write('type: $type, ')
          ..write('enabled: $enabled, ')
          ..write('order: $order')
          ..write(')'))
        .toString();
  }
}

class _$RuleSubInsertable implements Insertable<RuleSub> {
  RuleSub _object;
  _$RuleSubInsertable(this._object);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return RuleSubsCompanion(
      id: Value(_object.id),
      name: Value(_object.name),
      url: Value(_object.url),
      type: Value(_object.type),
      enabled: Value(_object.enabled),
      order: Value(_object.order),
    ).toColumns(false);
  }
}

extension RuleSubToInsertable on RuleSub {
  _$RuleSubInsertable toInsertable() {
    return _$RuleSubInsertable(this);
  }
}

class $SourceSubscriptionsTable extends SourceSubscriptions
    with TableInfo<$SourceSubscriptionsTable, SourceSubscription> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SourceSubscriptionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _orderMeta = const VerificationMeta('order');
  @override
  late final GeneratedColumn<int> order = GeneratedColumn<int>(
    'order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [url, name, type, enabled, order];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'source_subscriptions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SourceSubscription> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('order')) {
      context.handle(
        _orderMeta,
        order.isAcceptableOrUnknown(data['order']!, _orderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {url};
  @override
  SourceSubscription map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SourceSubscription(
      url:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}url'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      type:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}type'],
          )!,
      enabled:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}enabled'],
          )!,
      order:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}order'],
          )!,
    );
  }

  @override
  $SourceSubscriptionsTable createAlias(String alias) {
    return $SourceSubscriptionsTable(attachedDatabase, alias);
  }
}

class SourceSubscriptionsCompanion extends UpdateCompanion<SourceSubscription> {
  final Value<String> url;
  final Value<String> name;
  final Value<int> type;
  final Value<bool> enabled;
  final Value<int> order;
  final Value<int> rowid;
  const SourceSubscriptionsCompanion({
    this.url = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.enabled = const Value.absent(),
    this.order = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SourceSubscriptionsCompanion.insert({
    required String url,
    required String name,
    this.type = const Value.absent(),
    this.enabled = const Value.absent(),
    this.order = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : url = Value(url),
       name = Value(name);
  static Insertable<SourceSubscription> custom({
    Expression<String>? url,
    Expression<String>? name,
    Expression<int>? type,
    Expression<bool>? enabled,
    Expression<int>? order,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (url != null) 'url': url,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (enabled != null) 'enabled': enabled,
      if (order != null) 'order': order,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SourceSubscriptionsCompanion copyWith({
    Value<String>? url,
    Value<String>? name,
    Value<int>? type,
    Value<bool>? enabled,
    Value<int>? order,
    Value<int>? rowid,
  }) {
    return SourceSubscriptionsCompanion(
      url: url ?? this.url,
      name: name ?? this.name,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(type.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (order.present) {
      map['order'] = Variable<int>(order.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SourceSubscriptionsCompanion(')
          ..write('url: $url, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('enabled: $enabled, ')
          ..write('order: $order, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class _$SourceSubscriptionInsertable implements Insertable<SourceSubscription> {
  SourceSubscription _object;
  _$SourceSubscriptionInsertable(this._object);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return SourceSubscriptionsCompanion(
      url: Value(_object.url),
      name: Value(_object.name),
      type: Value(_object.type),
      enabled: Value(_object.enabled),
      order: Value(_object.order),
    ).toColumns(false);
  }
}

extension SourceSubscriptionToInsertable on SourceSubscription {
  _$SourceSubscriptionInsertable toInsertable() {
    return _$SourceSubscriptionInsertable(this);
  }
}

class $SearchBooksTable extends SearchBooks
    with TableInfo<$SearchBooksTable, SearchBook> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SearchBooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookUrlMeta = const VerificationMeta(
    'bookUrl',
  );
  @override
  late final GeneratedColumn<String> bookUrl = GeneratedColumn<String>(
    'bookUrl',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverUrlMeta = const VerificationMeta(
    'coverUrl',
  );
  @override
  late final GeneratedColumn<String> coverUrl = GeneratedColumn<String>(
    'coverUrl',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _introMeta = const VerificationMeta('intro');
  @override
  late final GeneratedColumn<String> intro = GeneratedColumn<String>(
    'intro',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _wordCountMeta = const VerificationMeta(
    'wordCount',
  );
  @override
  late final GeneratedColumn<String> wordCount = GeneratedColumn<String>(
    'wordCount',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latestChapterTitleMeta =
      const VerificationMeta('latestChapterTitle');
  @override
  late final GeneratedColumn<String> latestChapterTitle =
      GeneratedColumn<String>(
        'latestChapterTitle',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  late final GeneratedColumnWithTypeConverter<String, String> origin =
      GeneratedColumn<String>(
        'origin',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<String>($SearchBooksTable.$converterorigin);
  static const VerificationMeta _originNameMeta = const VerificationMeta(
    'originName',
  );
  @override
  late final GeneratedColumn<String> originName = GeneratedColumn<String>(
    'originName',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originOrderMeta = const VerificationMeta(
    'originOrder',
  );
  @override
  late final GeneratedColumn<int> originOrder = GeneratedColumn<int>(
    'originOrder',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _addTimeMeta = const VerificationMeta(
    'addTime',
  );
  @override
  late final GeneratedColumn<int> addTime = GeneratedColumn<int>(
    'addTime',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _variableMeta = const VerificationMeta(
    'variable',
  );
  @override
  late final GeneratedColumn<String> variable = GeneratedColumn<String>(
    'variable',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tocUrlMeta = const VerificationMeta('tocUrl');
  @override
  late final GeneratedColumn<String> tocUrl = GeneratedColumn<String>(
    'tocUrl',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    bookUrl,
    name,
    author,
    kind,
    coverUrl,
    intro,
    wordCount,
    latestChapterTitle,
    origin,
    originName,
    originOrder,
    type,
    addTime,
    variable,
    tocUrl,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'search_books';
  @override
  VerificationContext validateIntegrity(
    Insertable<SearchBook> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('bookUrl')) {
      context.handle(
        _bookUrlMeta,
        bookUrl.isAcceptableOrUnknown(data['bookUrl']!, _bookUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_bookUrlMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('coverUrl')) {
      context.handle(
        _coverUrlMeta,
        coverUrl.isAcceptableOrUnknown(data['coverUrl']!, _coverUrlMeta),
      );
    }
    if (data.containsKey('intro')) {
      context.handle(
        _introMeta,
        intro.isAcceptableOrUnknown(data['intro']!, _introMeta),
      );
    }
    if (data.containsKey('wordCount')) {
      context.handle(
        _wordCountMeta,
        wordCount.isAcceptableOrUnknown(data['wordCount']!, _wordCountMeta),
      );
    }
    if (data.containsKey('latestChapterTitle')) {
      context.handle(
        _latestChapterTitleMeta,
        latestChapterTitle.isAcceptableOrUnknown(
          data['latestChapterTitle']!,
          _latestChapterTitleMeta,
        ),
      );
    }
    if (data.containsKey('originName')) {
      context.handle(
        _originNameMeta,
        originName.isAcceptableOrUnknown(data['originName']!, _originNameMeta),
      );
    }
    if (data.containsKey('originOrder')) {
      context.handle(
        _originOrderMeta,
        originOrder.isAcceptableOrUnknown(
          data['originOrder']!,
          _originOrderMeta,
        ),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('addTime')) {
      context.handle(
        _addTimeMeta,
        addTime.isAcceptableOrUnknown(data['addTime']!, _addTimeMeta),
      );
    }
    if (data.containsKey('variable')) {
      context.handle(
        _variableMeta,
        variable.isAcceptableOrUnknown(data['variable']!, _variableMeta),
      );
    }
    if (data.containsKey('tocUrl')) {
      context.handle(
        _tocUrlMeta,
        tocUrl.isAcceptableOrUnknown(data['tocUrl']!, _tocUrlMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookUrl};
  @override
  SearchBook map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SearchBook(
      bookUrl:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}bookUrl'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      ),
      coverUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coverUrl'],
      ),
      intro: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intro'],
      ),
      wordCount: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wordCount'],
      ),
      latestChapterTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}latestChapterTitle'],
      ),
      origin: $SearchBooksTable.$converterorigin.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}origin'],
        ),
      ),
      originName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}originName'],
      ),
      originOrder:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}originOrder'],
          )!,
      type:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}type'],
          )!,
      addTime:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}addTime'],
          )!,
      variable: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variable'],
      ),
      tocUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tocUrl'],
      ),
    );
  }

  @override
  $SearchBooksTable createAlias(String alias) {
    return $SearchBooksTable(attachedDatabase, alias);
  }

  static TypeConverter<String, String?> $converterorigin =
      const EmptyStringConverter();
}

class SearchBooksCompanion extends UpdateCompanion<SearchBook> {
  final Value<String> bookUrl;
  final Value<String> name;
  final Value<String?> author;
  final Value<String?> kind;
  final Value<String?> coverUrl;
  final Value<String?> intro;
  final Value<String?> wordCount;
  final Value<String?> latestChapterTitle;
  final Value<String> origin;
  final Value<String?> originName;
  final Value<int> originOrder;
  final Value<int> type;
  final Value<int> addTime;
  final Value<String?> variable;
  final Value<String?> tocUrl;
  final Value<int> rowid;
  const SearchBooksCompanion({
    this.bookUrl = const Value.absent(),
    this.name = const Value.absent(),
    this.author = const Value.absent(),
    this.kind = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.intro = const Value.absent(),
    this.wordCount = const Value.absent(),
    this.latestChapterTitle = const Value.absent(),
    this.origin = const Value.absent(),
    this.originName = const Value.absent(),
    this.originOrder = const Value.absent(),
    this.type = const Value.absent(),
    this.addTime = const Value.absent(),
    this.variable = const Value.absent(),
    this.tocUrl = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SearchBooksCompanion.insert({
    required String bookUrl,
    required String name,
    this.author = const Value.absent(),
    this.kind = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.intro = const Value.absent(),
    this.wordCount = const Value.absent(),
    this.latestChapterTitle = const Value.absent(),
    this.origin = const Value.absent(),
    this.originName = const Value.absent(),
    this.originOrder = const Value.absent(),
    this.type = const Value.absent(),
    this.addTime = const Value.absent(),
    this.variable = const Value.absent(),
    this.tocUrl = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : bookUrl = Value(bookUrl),
       name = Value(name);
  static Insertable<SearchBook> custom({
    Expression<String>? bookUrl,
    Expression<String>? name,
    Expression<String>? author,
    Expression<String>? kind,
    Expression<String>? coverUrl,
    Expression<String>? intro,
    Expression<String>? wordCount,
    Expression<String>? latestChapterTitle,
    Expression<String>? origin,
    Expression<String>? originName,
    Expression<int>? originOrder,
    Expression<int>? type,
    Expression<int>? addTime,
    Expression<String>? variable,
    Expression<String>? tocUrl,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookUrl != null) 'bookUrl': bookUrl,
      if (name != null) 'name': name,
      if (author != null) 'author': author,
      if (kind != null) 'kind': kind,
      if (coverUrl != null) 'coverUrl': coverUrl,
      if (intro != null) 'intro': intro,
      if (wordCount != null) 'wordCount': wordCount,
      if (latestChapterTitle != null) 'latestChapterTitle': latestChapterTitle,
      if (origin != null) 'origin': origin,
      if (originName != null) 'originName': originName,
      if (originOrder != null) 'originOrder': originOrder,
      if (type != null) 'type': type,
      if (addTime != null) 'addTime': addTime,
      if (variable != null) 'variable': variable,
      if (tocUrl != null) 'tocUrl': tocUrl,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SearchBooksCompanion copyWith({
    Value<String>? bookUrl,
    Value<String>? name,
    Value<String?>? author,
    Value<String?>? kind,
    Value<String?>? coverUrl,
    Value<String?>? intro,
    Value<String?>? wordCount,
    Value<String?>? latestChapterTitle,
    Value<String>? origin,
    Value<String?>? originName,
    Value<int>? originOrder,
    Value<int>? type,
    Value<int>? addTime,
    Value<String?>? variable,
    Value<String?>? tocUrl,
    Value<int>? rowid,
  }) {
    return SearchBooksCompanion(
      bookUrl: bookUrl ?? this.bookUrl,
      name: name ?? this.name,
      author: author ?? this.author,
      kind: kind ?? this.kind,
      coverUrl: coverUrl ?? this.coverUrl,
      intro: intro ?? this.intro,
      wordCount: wordCount ?? this.wordCount,
      latestChapterTitle: latestChapterTitle ?? this.latestChapterTitle,
      origin: origin ?? this.origin,
      originName: originName ?? this.originName,
      originOrder: originOrder ?? this.originOrder,
      type: type ?? this.type,
      addTime: addTime ?? this.addTime,
      variable: variable ?? this.variable,
      tocUrl: tocUrl ?? this.tocUrl,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookUrl.present) {
      map['bookUrl'] = Variable<String>(bookUrl.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (coverUrl.present) {
      map['coverUrl'] = Variable<String>(coverUrl.value);
    }
    if (intro.present) {
      map['intro'] = Variable<String>(intro.value);
    }
    if (wordCount.present) {
      map['wordCount'] = Variable<String>(wordCount.value);
    }
    if (latestChapterTitle.present) {
      map['latestChapterTitle'] = Variable<String>(latestChapterTitle.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(
        $SearchBooksTable.$converterorigin.toSql(origin.value),
      );
    }
    if (originName.present) {
      map['originName'] = Variable<String>(originName.value);
    }
    if (originOrder.present) {
      map['originOrder'] = Variable<int>(originOrder.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(type.value);
    }
    if (addTime.present) {
      map['addTime'] = Variable<int>(addTime.value);
    }
    if (variable.present) {
      map['variable'] = Variable<String>(variable.value);
    }
    if (tocUrl.present) {
      map['tocUrl'] = Variable<String>(tocUrl.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SearchBooksCompanion(')
          ..write('bookUrl: $bookUrl, ')
          ..write('name: $name, ')
          ..write('author: $author, ')
          ..write('kind: $kind, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('intro: $intro, ')
          ..write('wordCount: $wordCount, ')
          ..write('latestChapterTitle: $latestChapterTitle, ')
          ..write('origin: $origin, ')
          ..write('originName: $originName, ')
          ..write('originOrder: $originOrder, ')
          ..write('type: $type, ')
          ..write('addTime: $addTime, ')
          ..write('variable: $variable, ')
          ..write('tocUrl: $tocUrl, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class _$SearchBookInsertable implements Insertable<SearchBook> {
  SearchBook _object;
  _$SearchBookInsertable(this._object);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return SearchBooksCompanion(
      bookUrl: Value(_object.bookUrl),
      name: Value(_object.name),
      author: Value(_object.author),
      kind: Value(_object.kind),
      coverUrl: Value(_object.coverUrl),
      intro: Value(_object.intro),
      wordCount: Value(_object.wordCount),
      latestChapterTitle: Value(_object.latestChapterTitle),
      origin: Value(_object.origin),
      originName: Value(_object.originName),
      originOrder: Value(_object.originOrder),
      type: Value(_object.type),
      addTime: Value(_object.addTime),
      variable: Value(_object.variable),
      tocUrl: Value(_object.tocUrl),
    ).toColumns(false);
  }
}

extension SearchBookToInsertable on SearchBook {
  _$SearchBookInsertable toInsertable() {
    return _$SearchBookInsertable(this);
  }
}

class $DownloadTasksTable extends DownloadTasks
    with TableInfo<$DownloadTasksTable, DownloadTask> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookUrlMeta = const VerificationMeta(
    'bookUrl',
  );
  @override
  late final GeneratedColumn<String> bookUrl = GeneratedColumn<String>(
    'bookUrl',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookNameMeta = const VerificationMeta(
    'bookName',
  );
  @override
  late final GeneratedColumn<String> bookName = GeneratedColumn<String>(
    'bookName',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startChapterIndexMeta = const VerificationMeta(
    'startChapterIndex',
  );
  @override
  late final GeneratedColumn<int> startChapterIndex = GeneratedColumn<int>(
    'startChapterIndex',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _endChapterIndexMeta = const VerificationMeta(
    'endChapterIndex',
  );
  @override
  late final GeneratedColumn<int> endChapterIndex = GeneratedColumn<int>(
    'endChapterIndex',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _currentChapterIndexMeta =
      const VerificationMeta('currentChapterIndex');
  @override
  late final GeneratedColumn<int> currentChapterIndex = GeneratedColumn<int>(
    'currentChapterIndex',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalCountMeta = const VerificationMeta(
    'totalCount',
  );
  @override
  late final GeneratedColumn<int> totalCount = GeneratedColumn<int>(
    'totalChapterCount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _successCountMeta = const VerificationMeta(
    'successCount',
  );
  @override
  late final GeneratedColumn<int> successCount = GeneratedColumn<int>(
    'successCount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _errorCountMeta = const VerificationMeta(
    'errorCount',
  );
  @override
  late final GeneratedColumn<int> errorCount = GeneratedColumn<int>(
    'errorCount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastUpdateTimeMeta = const VerificationMeta(
    'lastUpdateTime',
  );
  @override
  late final GeneratedColumn<int> lastUpdateTime = GeneratedColumn<int>(
    'addTime',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    bookUrl,
    bookName,
    startChapterIndex,
    endChapterIndex,
    currentChapterIndex,
    totalCount,
    status,
    successCount,
    errorCount,
    lastUpdateTime,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'download_tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<DownloadTask> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('bookUrl')) {
      context.handle(
        _bookUrlMeta,
        bookUrl.isAcceptableOrUnknown(data['bookUrl']!, _bookUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_bookUrlMeta);
    }
    if (data.containsKey('bookName')) {
      context.handle(
        _bookNameMeta,
        bookName.isAcceptableOrUnknown(data['bookName']!, _bookNameMeta),
      );
    } else if (isInserting) {
      context.missing(_bookNameMeta);
    }
    if (data.containsKey('startChapterIndex')) {
      context.handle(
        _startChapterIndexMeta,
        startChapterIndex.isAcceptableOrUnknown(
          data['startChapterIndex']!,
          _startChapterIndexMeta,
        ),
      );
    }
    if (data.containsKey('endChapterIndex')) {
      context.handle(
        _endChapterIndexMeta,
        endChapterIndex.isAcceptableOrUnknown(
          data['endChapterIndex']!,
          _endChapterIndexMeta,
        ),
      );
    }
    if (data.containsKey('currentChapterIndex')) {
      context.handle(
        _currentChapterIndexMeta,
        currentChapterIndex.isAcceptableOrUnknown(
          data['currentChapterIndex']!,
          _currentChapterIndexMeta,
        ),
      );
    }
    if (data.containsKey('totalChapterCount')) {
      context.handle(
        _totalCountMeta,
        totalCount.isAcceptableOrUnknown(
          data['totalChapterCount']!,
          _totalCountMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('successCount')) {
      context.handle(
        _successCountMeta,
        successCount.isAcceptableOrUnknown(
          data['successCount']!,
          _successCountMeta,
        ),
      );
    }
    if (data.containsKey('errorCount')) {
      context.handle(
        _errorCountMeta,
        errorCount.isAcceptableOrUnknown(data['errorCount']!, _errorCountMeta),
      );
    }
    if (data.containsKey('addTime')) {
      context.handle(
        _lastUpdateTimeMeta,
        lastUpdateTime.isAcceptableOrUnknown(
          data['addTime']!,
          _lastUpdateTimeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookUrl};
  @override
  DownloadTask map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DownloadTask(
      bookUrl:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}bookUrl'],
          )!,
      bookName:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}bookName'],
          )!,
      startChapterIndex:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}startChapterIndex'],
          )!,
      endChapterIndex:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}endChapterIndex'],
          )!,
      currentChapterIndex:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}currentChapterIndex'],
          )!,
      status:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}status'],
          )!,
      totalCount:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}totalChapterCount'],
          )!,
      successCount:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}successCount'],
          )!,
      errorCount:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}errorCount'],
          )!,
      lastUpdateTime:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}addTime'],
          )!,
    );
  }

  @override
  $DownloadTasksTable createAlias(String alias) {
    return $DownloadTasksTable(attachedDatabase, alias);
  }
}

class DownloadTasksCompanion extends UpdateCompanion<DownloadTask> {
  final Value<String> bookUrl;
  final Value<String> bookName;
  final Value<int> startChapterIndex;
  final Value<int> endChapterIndex;
  final Value<int> currentChapterIndex;
  final Value<int> totalCount;
  final Value<int> status;
  final Value<int> successCount;
  final Value<int> errorCount;
  final Value<int> lastUpdateTime;
  final Value<int> rowid;
  const DownloadTasksCompanion({
    this.bookUrl = const Value.absent(),
    this.bookName = const Value.absent(),
    this.startChapterIndex = const Value.absent(),
    this.endChapterIndex = const Value.absent(),
    this.currentChapterIndex = const Value.absent(),
    this.totalCount = const Value.absent(),
    this.status = const Value.absent(),
    this.successCount = const Value.absent(),
    this.errorCount = const Value.absent(),
    this.lastUpdateTime = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DownloadTasksCompanion.insert({
    required String bookUrl,
    required String bookName,
    this.startChapterIndex = const Value.absent(),
    this.endChapterIndex = const Value.absent(),
    this.currentChapterIndex = const Value.absent(),
    this.totalCount = const Value.absent(),
    this.status = const Value.absent(),
    this.successCount = const Value.absent(),
    this.errorCount = const Value.absent(),
    this.lastUpdateTime = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : bookUrl = Value(bookUrl),
       bookName = Value(bookName);
  static Insertable<DownloadTask> custom({
    Expression<String>? bookUrl,
    Expression<String>? bookName,
    Expression<int>? startChapterIndex,
    Expression<int>? endChapterIndex,
    Expression<int>? currentChapterIndex,
    Expression<int>? totalCount,
    Expression<int>? status,
    Expression<int>? successCount,
    Expression<int>? errorCount,
    Expression<int>? lastUpdateTime,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookUrl != null) 'bookUrl': bookUrl,
      if (bookName != null) 'bookName': bookName,
      if (startChapterIndex != null) 'startChapterIndex': startChapterIndex,
      if (endChapterIndex != null) 'endChapterIndex': endChapterIndex,
      if (currentChapterIndex != null)
        'currentChapterIndex': currentChapterIndex,
      if (totalCount != null) 'totalChapterCount': totalCount,
      if (status != null) 'status': status,
      if (successCount != null) 'successCount': successCount,
      if (errorCount != null) 'errorCount': errorCount,
      if (lastUpdateTime != null) 'addTime': lastUpdateTime,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DownloadTasksCompanion copyWith({
    Value<String>? bookUrl,
    Value<String>? bookName,
    Value<int>? startChapterIndex,
    Value<int>? endChapterIndex,
    Value<int>? currentChapterIndex,
    Value<int>? totalCount,
    Value<int>? status,
    Value<int>? successCount,
    Value<int>? errorCount,
    Value<int>? lastUpdateTime,
    Value<int>? rowid,
  }) {
    return DownloadTasksCompanion(
      bookUrl: bookUrl ?? this.bookUrl,
      bookName: bookName ?? this.bookName,
      startChapterIndex: startChapterIndex ?? this.startChapterIndex,
      endChapterIndex: endChapterIndex ?? this.endChapterIndex,
      currentChapterIndex: currentChapterIndex ?? this.currentChapterIndex,
      totalCount: totalCount ?? this.totalCount,
      status: status ?? this.status,
      successCount: successCount ?? this.successCount,
      errorCount: errorCount ?? this.errorCount,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookUrl.present) {
      map['bookUrl'] = Variable<String>(bookUrl.value);
    }
    if (bookName.present) {
      map['bookName'] = Variable<String>(bookName.value);
    }
    if (startChapterIndex.present) {
      map['startChapterIndex'] = Variable<int>(startChapterIndex.value);
    }
    if (endChapterIndex.present) {
      map['endChapterIndex'] = Variable<int>(endChapterIndex.value);
    }
    if (currentChapterIndex.present) {
      map['currentChapterIndex'] = Variable<int>(currentChapterIndex.value);
    }
    if (totalCount.present) {
      map['totalChapterCount'] = Variable<int>(totalCount.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (successCount.present) {
      map['successCount'] = Variable<int>(successCount.value);
    }
    if (errorCount.present) {
      map['errorCount'] = Variable<int>(errorCount.value);
    }
    if (lastUpdateTime.present) {
      map['addTime'] = Variable<int>(lastUpdateTime.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DownloadTasksCompanion(')
          ..write('bookUrl: $bookUrl, ')
          ..write('bookName: $bookName, ')
          ..write('startChapterIndex: $startChapterIndex, ')
          ..write('endChapterIndex: $endChapterIndex, ')
          ..write('currentChapterIndex: $currentChapterIndex, ')
          ..write('totalCount: $totalCount, ')
          ..write('status: $status, ')
          ..write('successCount: $successCount, ')
          ..write('errorCount: $errorCount, ')
          ..write('lastUpdateTime: $lastUpdateTime, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class _$DownloadTaskInsertable implements Insertable<DownloadTask> {
  DownloadTask _object;
  _$DownloadTaskInsertable(this._object);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return DownloadTasksCompanion(
      bookUrl: Value(_object.bookUrl),
      bookName: Value(_object.bookName),
      startChapterIndex: Value(_object.startChapterIndex),
      endChapterIndex: Value(_object.endChapterIndex),
      currentChapterIndex: Value(_object.currentChapterIndex),
      totalCount: Value(_object.totalCount),
      status: Value(_object.status),
      successCount: Value(_object.successCount),
      errorCount: Value(_object.errorCount),
      lastUpdateTime: Value(_object.lastUpdateTime),
    ).toColumns(false);
  }
}

extension DownloadTaskToInsertable on DownloadTask {
  _$DownloadTaskInsertable toInsertable() {
    return _$DownloadTaskInsertable(this);
  }
}

class $SearchKeywordsTable extends SearchKeywords
    with TableInfo<$SearchKeywordsTable, SearchKeyword> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SearchKeywordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _wordMeta = const VerificationMeta('word');
  @override
  late final GeneratedColumn<String> word = GeneratedColumn<String>(
    'word',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usageMeta = const VerificationMeta('usage');
  @override
  late final GeneratedColumn<int> usage = GeneratedColumn<int>(
    'usage',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastUseTimeMeta = const VerificationMeta(
    'lastUseTime',
  );
  @override
  late final GeneratedColumn<int> lastUseTime = GeneratedColumn<int>(
    'lastUseTime',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [word, usage, lastUseTime];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'search_keywords';
  @override
  VerificationContext validateIntegrity(
    Insertable<SearchKeyword> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('word')) {
      context.handle(
        _wordMeta,
        word.isAcceptableOrUnknown(data['word']!, _wordMeta),
      );
    } else if (isInserting) {
      context.missing(_wordMeta);
    }
    if (data.containsKey('usage')) {
      context.handle(
        _usageMeta,
        usage.isAcceptableOrUnknown(data['usage']!, _usageMeta),
      );
    }
    if (data.containsKey('lastUseTime')) {
      context.handle(
        _lastUseTimeMeta,
        lastUseTime.isAcceptableOrUnknown(
          data['lastUseTime']!,
          _lastUseTimeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {word};
  @override
  SearchKeyword map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SearchKeyword(
      word:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}word'],
          )!,
      usage:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}usage'],
          )!,
      lastUseTime:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}lastUseTime'],
          )!,
    );
  }

  @override
  $SearchKeywordsTable createAlias(String alias) {
    return $SearchKeywordsTable(attachedDatabase, alias);
  }
}

class SearchKeywordsCompanion extends UpdateCompanion<SearchKeyword> {
  final Value<String> word;
  final Value<int> usage;
  final Value<int> lastUseTime;
  final Value<int> rowid;
  const SearchKeywordsCompanion({
    this.word = const Value.absent(),
    this.usage = const Value.absent(),
    this.lastUseTime = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SearchKeywordsCompanion.insert({
    required String word,
    this.usage = const Value.absent(),
    this.lastUseTime = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : word = Value(word);
  static Insertable<SearchKeyword> custom({
    Expression<String>? word,
    Expression<int>? usage,
    Expression<int>? lastUseTime,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (word != null) 'word': word,
      if (usage != null) 'usage': usage,
      if (lastUseTime != null) 'lastUseTime': lastUseTime,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SearchKeywordsCompanion copyWith({
    Value<String>? word,
    Value<int>? usage,
    Value<int>? lastUseTime,
    Value<int>? rowid,
  }) {
    return SearchKeywordsCompanion(
      word: word ?? this.word,
      usage: usage ?? this.usage,
      lastUseTime: lastUseTime ?? this.lastUseTime,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (word.present) {
      map['word'] = Variable<String>(word.value);
    }
    if (usage.present) {
      map['usage'] = Variable<int>(usage.value);
    }
    if (lastUseTime.present) {
      map['lastUseTime'] = Variable<int>(lastUseTime.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SearchKeywordsCompanion(')
          ..write('word: $word, ')
          ..write('usage: $usage, ')
          ..write('lastUseTime: $lastUseTime, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class _$SearchKeywordInsertable implements Insertable<SearchKeyword> {
  SearchKeyword _object;
  _$SearchKeywordInsertable(this._object);
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return SearchKeywordsCompanion(
      word: Value(_object.word),
      usage: Value(_object.usage),
      lastUseTime: Value(_object.lastUseTime),
    ).toColumns(false);
  }
}

extension SearchKeywordToInsertable on SearchKeyword {
  _$SearchKeywordInsertable toInsertable() {
    return _$SearchKeywordInsertable(this);
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $BooksTable books = $BooksTable(this);
  late final $ChaptersTable chapters = $ChaptersTable(this);
  late final $ReaderChapterContentsTable readerChapterContents =
      $ReaderChapterContentsTable(this);
  late final $BookSourcesTable bookSources = $BookSourcesTable(this);
  late final $BookGroupsTable bookGroups = $BookGroupsTable(this);
  late final $SearchHistoryTableTable searchHistoryTable =
      $SearchHistoryTableTable(this);
  late final $ReplaceRulesTable replaceRules = $ReplaceRulesTable(this);
  late final $BookmarksTable bookmarks = $BookmarksTable(this);
  late final $CookiesTable cookies = $CookiesTable(this);
  late final $DictRulesTable dictRules = $DictRulesTable(this);
  late final $HttpTtsTableTable httpTtsTable = $HttpTtsTableTable(this);
  late final $ReadRecordsTable readRecords = $ReadRecordsTable(this);
  late final $ServersTable servers = $ServersTable(this);
  late final $TxtTocRulesTable txtTocRules = $TxtTocRulesTable(this);
  late final $CacheTableTable cacheTable = $CacheTableTable(this);
  late final $KeyboardAssistsTable keyboardAssists = $KeyboardAssistsTable(
    this,
  );
  late final $RuleSubsTable ruleSubs = $RuleSubsTable(this);
  late final $SourceSubscriptionsTable sourceSubscriptions =
      $SourceSubscriptionsTable(this);
  late final $SearchBooksTable searchBooks = $SearchBooksTable(this);
  late final $DownloadTasksTable downloadTasks = $DownloadTasksTable(this);
  late final $SearchKeywordsTable searchKeywords = $SearchKeywordsTable(this);
  late final BookDao bookDao = BookDao(this as AppDatabase);
  late final ChapterDao chapterDao = ChapterDao(this as AppDatabase);
  late final BookSourceDao bookSourceDao = BookSourceDao(this as AppDatabase);
  late final BookGroupDao bookGroupDao = BookGroupDao(this as AppDatabase);
  late final BookmarkDao bookmarkDao = BookmarkDao(this as AppDatabase);
  late final ReplaceRuleDao replaceRuleDao = ReplaceRuleDao(
    this as AppDatabase,
  );
  late final SearchHistoryDao searchHistoryDao = SearchHistoryDao(
    this as AppDatabase,
  );
  late final CookieDao cookieDao = CookieDao(this as AppDatabase);
  late final DictRuleDao dictRuleDao = DictRuleDao(this as AppDatabase);
  late final HttpTtsDao httpTtsDao = HttpTtsDao(this as AppDatabase);
  late final ReadRecordDao readRecordDao = ReadRecordDao(this as AppDatabase);
  late final ServerDao serverDao = ServerDao(this as AppDatabase);
  late final TxtTocRuleDao txtTocRuleDao = TxtTocRuleDao(this as AppDatabase);
  late final CacheDao cacheDao = CacheDao(this as AppDatabase);
  late final KeyboardAssistDao keyboardAssistDao = KeyboardAssistDao(
    this as AppDatabase,
  );
  late final RuleSubDao ruleSubDao = RuleSubDao(this as AppDatabase);
  late final SourceSubscriptionDao sourceSubscriptionDao =
      SourceSubscriptionDao(this as AppDatabase);
  late final SearchBookDao searchBookDao = SearchBookDao(this as AppDatabase);
  late final DownloadDao downloadDao = DownloadDao(this as AppDatabase);
  late final SearchKeywordDao searchKeywordDao = SearchKeywordDao(
    this as AppDatabase,
  );
  late final ReaderChapterContentDao readerChapterContentDao =
      ReaderChapterContentDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    books,
    chapters,
    readerChapterContents,
    bookSources,
    bookGroups,
    searchHistoryTable,
    replaceRules,
    bookmarks,
    cookies,
    dictRules,
    httpTtsTable,
    readRecords,
    servers,
    txtTocRules,
    cacheTable,
    keyboardAssists,
    ruleSubs,
    sourceSubscriptions,
    searchBooks,
    downloadTasks,
    searchKeywords,
  ];
}

typedef $$BooksTableCreateCompanionBuilder =
    BooksCompanion Function({
      required String bookUrl,
      Value<String> tocUrl,
      Value<String> origin,
      Value<String> originName,
      required String name,
      Value<String> author,
      Value<String?> kind,
      Value<String?> customTag,
      Value<String?> coverUrl,
      Value<String?> coverLocalPath,
      Value<String?> customCoverUrl,
      Value<String?> customCoverLocalPath,
      Value<String?> intro,
      Value<String?> customIntro,
      Value<String?> charset,
      Value<int> type,
      Value<int> group,
      Value<String?> latestChapterTitle,
      Value<int> latestChapterTime,
      Value<int> lastCheckTime,
      Value<int> lastCheckCount,
      Value<int> totalChapterNum,
      Value<String?> durChapterTitle,
      Value<int> chapterIndex,
      Value<int> charOffset,
      Value<double> visualOffsetPx,
      Value<String?> readerAnchorJson,
      Value<int> durChapterTime,
      Value<String?> wordCount,
      Value<bool> canUpdate,
      Value<int> order,
      Value<int> originOrder,
      Value<String?> variable,
      Value<ReadConfig?> readConfig,
      Value<int> syncTime,
      Value<bool> isInBookshelf,
      Value<int> rowid,
    });
typedef $$BooksTableUpdateCompanionBuilder =
    BooksCompanion Function({
      Value<String> bookUrl,
      Value<String> tocUrl,
      Value<String> origin,
      Value<String> originName,
      Value<String> name,
      Value<String> author,
      Value<String?> kind,
      Value<String?> customTag,
      Value<String?> coverUrl,
      Value<String?> coverLocalPath,
      Value<String?> customCoverUrl,
      Value<String?> customCoverLocalPath,
      Value<String?> intro,
      Value<String?> customIntro,
      Value<String?> charset,
      Value<int> type,
      Value<int> group,
      Value<String?> latestChapterTitle,
      Value<int> latestChapterTime,
      Value<int> lastCheckTime,
      Value<int> lastCheckCount,
      Value<int> totalChapterNum,
      Value<String?> durChapterTitle,
      Value<int> chapterIndex,
      Value<int> charOffset,
      Value<double> visualOffsetPx,
      Value<String?> readerAnchorJson,
      Value<int> durChapterTime,
      Value<String?> wordCount,
      Value<bool> canUpdate,
      Value<int> order,
      Value<int> originOrder,
      Value<String?> variable,
      Value<ReadConfig?> readConfig,
      Value<int> syncTime,
      Value<bool> isInBookshelf,
      Value<int> rowid,
    });

class $$BooksTableFilterComposer extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<String, String, String> get tocUrl =>
      $composableBuilder(
        column: $table.tocUrl,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<String, String, String> get origin =>
      $composableBuilder(
        column: $table.origin,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<String, String, String> get originName =>
      $composableBuilder(
        column: $table.originName,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<String, String, String> get author =>
      $composableBuilder(
        column: $table.author,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customTag => $composableBuilder(
    column: $table.customTag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverLocalPath => $composableBuilder(
    column: $table.coverLocalPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customCoverUrl => $composableBuilder(
    column: $table.customCoverUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customCoverLocalPath => $composableBuilder(
    column: $table.customCoverLocalPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get intro => $composableBuilder(
    column: $table.intro,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customIntro => $composableBuilder(
    column: $table.customIntro,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get charset => $composableBuilder(
    column: $table.charset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get group => $composableBuilder(
    column: $table.group,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get latestChapterTitle => $composableBuilder(
    column: $table.latestChapterTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get latestChapterTime => $composableBuilder(
    column: $table.latestChapterTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastCheckTime => $composableBuilder(
    column: $table.lastCheckTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastCheckCount => $composableBuilder(
    column: $table.lastCheckCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalChapterNum => $composableBuilder(
    column: $table.totalChapterNum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get durChapterTitle => $composableBuilder(
    column: $table.durChapterTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get visualOffsetPx => $composableBuilder(
    column: $table.visualOffsetPx,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get readerAnchorJson => $composableBuilder(
    column: $table.readerAnchorJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durChapterTime => $composableBuilder(
    column: $table.durChapterTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wordCount => $composableBuilder(
    column: $table.wordCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get canUpdate => $composableBuilder(
    column: $table.canUpdate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get order => $composableBuilder(
    column: $table.order,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get originOrder => $composableBuilder(
    column: $table.originOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get variable => $composableBuilder(
    column: $table.variable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ReadConfig?, ReadConfig, String>
  get readConfig => $composableBuilder(
    column: $table.readConfig,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get syncTime => $composableBuilder(
    column: $table.syncTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isInBookshelf => $composableBuilder(
    column: $table.isInBookshelf,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BooksTableOrderingComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tocUrl => $composableBuilder(
    column: $table.tocUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originName => $composableBuilder(
    column: $table.originName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customTag => $composableBuilder(
    column: $table.customTag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverLocalPath => $composableBuilder(
    column: $table.coverLocalPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customCoverUrl => $composableBuilder(
    column: $table.customCoverUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customCoverLocalPath => $composableBuilder(
    column: $table.customCoverLocalPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get intro => $composableBuilder(
    column: $table.intro,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customIntro => $composableBuilder(
    column: $table.customIntro,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get charset => $composableBuilder(
    column: $table.charset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get group => $composableBuilder(
    column: $table.group,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get latestChapterTitle => $composableBuilder(
    column: $table.latestChapterTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get latestChapterTime => $composableBuilder(
    column: $table.latestChapterTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastCheckTime => $composableBuilder(
    column: $table.lastCheckTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastCheckCount => $composableBuilder(
    column: $table.lastCheckCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalChapterNum => $composableBuilder(
    column: $table.totalChapterNum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get durChapterTitle => $composableBuilder(
    column: $table.durChapterTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get visualOffsetPx => $composableBuilder(
    column: $table.visualOffsetPx,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get readerAnchorJson => $composableBuilder(
    column: $table.readerAnchorJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durChapterTime => $composableBuilder(
    column: $table.durChapterTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wordCount => $composableBuilder(
    column: $table.wordCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get canUpdate => $composableBuilder(
    column: $table.canUpdate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get order => $composableBuilder(
    column: $table.order,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get originOrder => $composableBuilder(
    column: $table.originOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get variable => $composableBuilder(
    column: $table.variable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get readConfig => $composableBuilder(
    column: $table.readConfig,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncTime => $composableBuilder(
    column: $table.syncTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isInBookshelf => $composableBuilder(
    column: $table.isInBookshelf,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BooksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookUrl =>
      $composableBuilder(column: $table.bookUrl, builder: (column) => column);

  GeneratedColumnWithTypeConverter<String, String> get tocUrl =>
      $composableBuilder(column: $table.tocUrl, builder: (column) => column);

  GeneratedColumnWithTypeConverter<String, String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumnWithTypeConverter<String, String> get originName =>
      $composableBuilder(
        column: $table.originName,
        builder: (column) => column,
      );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumnWithTypeConverter<String, String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get customTag =>
      $composableBuilder(column: $table.customTag, builder: (column) => column);

  GeneratedColumn<String> get coverUrl =>
      $composableBuilder(column: $table.coverUrl, builder: (column) => column);

  GeneratedColumn<String> get coverLocalPath => $composableBuilder(
    column: $table.coverLocalPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customCoverUrl => $composableBuilder(
    column: $table.customCoverUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customCoverLocalPath => $composableBuilder(
    column: $table.customCoverLocalPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get intro =>
      $composableBuilder(column: $table.intro, builder: (column) => column);

  GeneratedColumn<String> get customIntro => $composableBuilder(
    column: $table.customIntro,
    builder: (column) => column,
  );

  GeneratedColumn<String> get charset =>
      $composableBuilder(column: $table.charset, builder: (column) => column);

  GeneratedColumn<int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get group =>
      $composableBuilder(column: $table.group, builder: (column) => column);

  GeneratedColumn<String> get latestChapterTitle => $composableBuilder(
    column: $table.latestChapterTitle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get latestChapterTime => $composableBuilder(
    column: $table.latestChapterTime,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastCheckTime => $composableBuilder(
    column: $table.lastCheckTime,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastCheckCount => $composableBuilder(
    column: $table.lastCheckCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalChapterNum => $composableBuilder(
    column: $table.totalChapterNum,
    builder: (column) => column,
  );

  GeneratedColumn<String> get durChapterTitle => $composableBuilder(
    column: $table.durChapterTitle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => column,
  );

  GeneratedColumn<double> get visualOffsetPx => $composableBuilder(
    column: $table.visualOffsetPx,
    builder: (column) => column,
  );

  GeneratedColumn<String> get readerAnchorJson => $composableBuilder(
    column: $table.readerAnchorJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durChapterTime => $composableBuilder(
    column: $table.durChapterTime,
    builder: (column) => column,
  );

  GeneratedColumn<String> get wordCount =>
      $composableBuilder(column: $table.wordCount, builder: (column) => column);

  GeneratedColumn<bool> get canUpdate =>
      $composableBuilder(column: $table.canUpdate, builder: (column) => column);

  GeneratedColumn<int> get order =>
      $composableBuilder(column: $table.order, builder: (column) => column);

  GeneratedColumn<int> get originOrder => $composableBuilder(
    column: $table.originOrder,
    builder: (column) => column,
  );

  GeneratedColumn<String> get variable =>
      $composableBuilder(column: $table.variable, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ReadConfig?, String> get readConfig =>
      $composableBuilder(
        column: $table.readConfig,
        builder: (column) => column,
      );

  GeneratedColumn<int> get syncTime =>
      $composableBuilder(column: $table.syncTime, builder: (column) => column);

  GeneratedColumn<bool> get isInBookshelf => $composableBuilder(
    column: $table.isInBookshelf,
    builder: (column) => column,
  );
}

class $$BooksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BooksTable,
          Book,
          $$BooksTableFilterComposer,
          $$BooksTableOrderingComposer,
          $$BooksTableAnnotationComposer,
          $$BooksTableCreateCompanionBuilder,
          $$BooksTableUpdateCompanionBuilder,
          (Book, BaseReferences<_$AppDatabase, $BooksTable, Book>),
          Book,
          PrefetchHooks Function()
        > {
  $$BooksTableTableManager(_$AppDatabase db, $BooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$BooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$BooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$BooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookUrl = const Value.absent(),
                Value<String> tocUrl = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String> originName = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> author = const Value.absent(),
                Value<String?> kind = const Value.absent(),
                Value<String?> customTag = const Value.absent(),
                Value<String?> coverUrl = const Value.absent(),
                Value<String?> coverLocalPath = const Value.absent(),
                Value<String?> customCoverUrl = const Value.absent(),
                Value<String?> customCoverLocalPath = const Value.absent(),
                Value<String?> intro = const Value.absent(),
                Value<String?> customIntro = const Value.absent(),
                Value<String?> charset = const Value.absent(),
                Value<int> type = const Value.absent(),
                Value<int> group = const Value.absent(),
                Value<String?> latestChapterTitle = const Value.absent(),
                Value<int> latestChapterTime = const Value.absent(),
                Value<int> lastCheckTime = const Value.absent(),
                Value<int> lastCheckCount = const Value.absent(),
                Value<int> totalChapterNum = const Value.absent(),
                Value<String?> durChapterTitle = const Value.absent(),
                Value<int> chapterIndex = const Value.absent(),
                Value<int> charOffset = const Value.absent(),
                Value<double> visualOffsetPx = const Value.absent(),
                Value<String?> readerAnchorJson = const Value.absent(),
                Value<int> durChapterTime = const Value.absent(),
                Value<String?> wordCount = const Value.absent(),
                Value<bool> canUpdate = const Value.absent(),
                Value<int> order = const Value.absent(),
                Value<int> originOrder = const Value.absent(),
                Value<String?> variable = const Value.absent(),
                Value<ReadConfig?> readConfig = const Value.absent(),
                Value<int> syncTime = const Value.absent(),
                Value<bool> isInBookshelf = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion(
                bookUrl: bookUrl,
                tocUrl: tocUrl,
                origin: origin,
                originName: originName,
                name: name,
                author: author,
                kind: kind,
                customTag: customTag,
                coverUrl: coverUrl,
                coverLocalPath: coverLocalPath,
                customCoverUrl: customCoverUrl,
                customCoverLocalPath: customCoverLocalPath,
                intro: intro,
                customIntro: customIntro,
                charset: charset,
                type: type,
                group: group,
                latestChapterTitle: latestChapterTitle,
                latestChapterTime: latestChapterTime,
                lastCheckTime: lastCheckTime,
                lastCheckCount: lastCheckCount,
                totalChapterNum: totalChapterNum,
                durChapterTitle: durChapterTitle,
                chapterIndex: chapterIndex,
                charOffset: charOffset,
                visualOffsetPx: visualOffsetPx,
                readerAnchorJson: readerAnchorJson,
                durChapterTime: durChapterTime,
                wordCount: wordCount,
                canUpdate: canUpdate,
                order: order,
                originOrder: originOrder,
                variable: variable,
                readConfig: readConfig,
                syncTime: syncTime,
                isInBookshelf: isInBookshelf,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookUrl,
                Value<String> tocUrl = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String> originName = const Value.absent(),
                required String name,
                Value<String> author = const Value.absent(),
                Value<String?> kind = const Value.absent(),
                Value<String?> customTag = const Value.absent(),
                Value<String?> coverUrl = const Value.absent(),
                Value<String?> coverLocalPath = const Value.absent(),
                Value<String?> customCoverUrl = const Value.absent(),
                Value<String?> customCoverLocalPath = const Value.absent(),
                Value<String?> intro = const Value.absent(),
                Value<String?> customIntro = const Value.absent(),
                Value<String?> charset = const Value.absent(),
                Value<int> type = const Value.absent(),
                Value<int> group = const Value.absent(),
                Value<String?> latestChapterTitle = const Value.absent(),
                Value<int> latestChapterTime = const Value.absent(),
                Value<int> lastCheckTime = const Value.absent(),
                Value<int> lastCheckCount = const Value.absent(),
                Value<int> totalChapterNum = const Value.absent(),
                Value<String?> durChapterTitle = const Value.absent(),
                Value<int> chapterIndex = const Value.absent(),
                Value<int> charOffset = const Value.absent(),
                Value<double> visualOffsetPx = const Value.absent(),
                Value<String?> readerAnchorJson = const Value.absent(),
                Value<int> durChapterTime = const Value.absent(),
                Value<String?> wordCount = const Value.absent(),
                Value<bool> canUpdate = const Value.absent(),
                Value<int> order = const Value.absent(),
                Value<int> originOrder = const Value.absent(),
                Value<String?> variable = const Value.absent(),
                Value<ReadConfig?> readConfig = const Value.absent(),
                Value<int> syncTime = const Value.absent(),
                Value<bool> isInBookshelf = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion.insert(
                bookUrl: bookUrl,
                tocUrl: tocUrl,
                origin: origin,
                originName: originName,
                name: name,
                author: author,
                kind: kind,
                customTag: customTag,
                coverUrl: coverUrl,
                coverLocalPath: coverLocalPath,
                customCoverUrl: customCoverUrl,
                customCoverLocalPath: customCoverLocalPath,
                intro: intro,
                customIntro: customIntro,
                charset: charset,
                type: type,
                group: group,
                latestChapterTitle: latestChapterTitle,
                latestChapterTime: latestChapterTime,
                lastCheckTime: lastCheckTime,
                lastCheckCount: lastCheckCount,
                totalChapterNum: totalChapterNum,
                durChapterTitle: durChapterTitle,
                chapterIndex: chapterIndex,
                charOffset: charOffset,
                visualOffsetPx: visualOffsetPx,
                readerAnchorJson: readerAnchorJson,
                durChapterTime: durChapterTime,
                wordCount: wordCount,
                canUpdate: canUpdate,
                order: order,
                originOrder: originOrder,
                variable: variable,
                readConfig: readConfig,
                syncTime: syncTime,
                isInBookshelf: isInBookshelf,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BooksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BooksTable,
      Book,
      $$BooksTableFilterComposer,
      $$BooksTableOrderingComposer,
      $$BooksTableAnnotationComposer,
      $$BooksTableCreateCompanionBuilder,
      $$BooksTableUpdateCompanionBuilder,
      (Book, BaseReferences<_$AppDatabase, $BooksTable, Book>),
      Book,
      PrefetchHooks Function()
    >;
typedef $$ChaptersTableCreateCompanionBuilder =
    ChaptersCompanion Function({
      required String url,
      required String title,
      Value<bool> isVolume,
      Value<String> baseUrl,
      required String bookUrl,
      required int index,
      Value<bool> isVip,
      Value<bool> isPay,
      Value<String?> resourceUrl,
      Value<String?> tag,
      Value<String?> wordCount,
      Value<int?> start,
      Value<int?> end,
      Value<String?> startFragmentId,
      Value<String?> endFragmentId,
      Value<String?> variable,
      Value<int> rowid,
    });
typedef $$ChaptersTableUpdateCompanionBuilder =
    ChaptersCompanion Function({
      Value<String> url,
      Value<String> title,
      Value<bool> isVolume,
      Value<String> baseUrl,
      Value<String> bookUrl,
      Value<int> index,
      Value<bool> isVip,
      Value<bool> isPay,
      Value<String?> resourceUrl,
      Value<String?> tag,
      Value<String?> wordCount,
      Value<int?> start,
      Value<int?> end,
      Value<String?> startFragmentId,
      Value<String?> endFragmentId,
      Value<String?> variable,
      Value<int> rowid,
    });

class $$ChaptersTableFilterComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isVolume => $composableBuilder(
    column: $table.isVolume,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<String, String, String> get baseUrl =>
      $composableBuilder(
        column: $table.baseUrl,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get index => $composableBuilder(
    column: $table.index,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isVip => $composableBuilder(
    column: $table.isVip,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPay => $composableBuilder(
    column: $table.isPay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resourceUrl => $composableBuilder(
    column: $table.resourceUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wordCount => $composableBuilder(
    column: $table.wordCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get start => $composableBuilder(
    column: $table.start,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get end => $composableBuilder(
    column: $table.end,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startFragmentId => $composableBuilder(
    column: $table.startFragmentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endFragmentId => $composableBuilder(
    column: $table.endFragmentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get variable => $composableBuilder(
    column: $table.variable,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChaptersTableOrderingComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isVolume => $composableBuilder(
    column: $table.isVolume,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get index => $composableBuilder(
    column: $table.index,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isVip => $composableBuilder(
    column: $table.isVip,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPay => $composableBuilder(
    column: $table.isPay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resourceUrl => $composableBuilder(
    column: $table.resourceUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wordCount => $composableBuilder(
    column: $table.wordCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get start => $composableBuilder(
    column: $table.start,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get end => $composableBuilder(
    column: $table.end,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startFragmentId => $composableBuilder(
    column: $table.startFragmentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endFragmentId => $composableBuilder(
    column: $table.endFragmentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get variable => $composableBuilder(
    column: $table.variable,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChaptersTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<bool> get isVolume =>
      $composableBuilder(column: $table.isVolume, builder: (column) => column);

  GeneratedColumnWithTypeConverter<String, String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumn<String> get bookUrl =>
      $composableBuilder(column: $table.bookUrl, builder: (column) => column);

  GeneratedColumn<int> get index =>
      $composableBuilder(column: $table.index, builder: (column) => column);

  GeneratedColumn<bool> get isVip =>
      $composableBuilder(column: $table.isVip, builder: (column) => column);

  GeneratedColumn<bool> get isPay =>
      $composableBuilder(column: $table.isPay, builder: (column) => column);

  GeneratedColumn<String> get resourceUrl => $composableBuilder(
    column: $table.resourceUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tag =>
      $composableBuilder(column: $table.tag, builder: (column) => column);

  GeneratedColumn<String> get wordCount =>
      $composableBuilder(column: $table.wordCount, builder: (column) => column);

  GeneratedColumn<int> get start =>
      $composableBuilder(column: $table.start, builder: (column) => column);

  GeneratedColumn<int> get end =>
      $composableBuilder(column: $table.end, builder: (column) => column);

  GeneratedColumn<String> get startFragmentId => $composableBuilder(
    column: $table.startFragmentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get endFragmentId => $composableBuilder(
    column: $table.endFragmentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get variable =>
      $composableBuilder(column: $table.variable, builder: (column) => column);
}

class $$ChaptersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChaptersTable,
          BookChapter,
          $$ChaptersTableFilterComposer,
          $$ChaptersTableOrderingComposer,
          $$ChaptersTableAnnotationComposer,
          $$ChaptersTableCreateCompanionBuilder,
          $$ChaptersTableUpdateCompanionBuilder,
          (
            BookChapter,
            BaseReferences<_$AppDatabase, $ChaptersTable, BookChapter>,
          ),
          BookChapter,
          PrefetchHooks Function()
        > {
  $$ChaptersTableTableManager(_$AppDatabase db, $ChaptersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$ChaptersTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$ChaptersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$ChaptersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> url = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<bool> isVolume = const Value.absent(),
                Value<String> baseUrl = const Value.absent(),
                Value<String> bookUrl = const Value.absent(),
                Value<int> index = const Value.absent(),
                Value<bool> isVip = const Value.absent(),
                Value<bool> isPay = const Value.absent(),
                Value<String?> resourceUrl = const Value.absent(),
                Value<String?> tag = const Value.absent(),
                Value<String?> wordCount = const Value.absent(),
                Value<int?> start = const Value.absent(),
                Value<int?> end = const Value.absent(),
                Value<String?> startFragmentId = const Value.absent(),
                Value<String?> endFragmentId = const Value.absent(),
                Value<String?> variable = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChaptersCompanion(
                url: url,
                title: title,
                isVolume: isVolume,
                baseUrl: baseUrl,
                bookUrl: bookUrl,
                index: index,
                isVip: isVip,
                isPay: isPay,
                resourceUrl: resourceUrl,
                tag: tag,
                wordCount: wordCount,
                start: start,
                end: end,
                startFragmentId: startFragmentId,
                endFragmentId: endFragmentId,
                variable: variable,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String url,
                required String title,
                Value<bool> isVolume = const Value.absent(),
                Value<String> baseUrl = const Value.absent(),
                required String bookUrl,
                required int index,
                Value<bool> isVip = const Value.absent(),
                Value<bool> isPay = const Value.absent(),
                Value<String?> resourceUrl = const Value.absent(),
                Value<String?> tag = const Value.absent(),
                Value<String?> wordCount = const Value.absent(),
                Value<int?> start = const Value.absent(),
                Value<int?> end = const Value.absent(),
                Value<String?> startFragmentId = const Value.absent(),
                Value<String?> endFragmentId = const Value.absent(),
                Value<String?> variable = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChaptersCompanion.insert(
                url: url,
                title: title,
                isVolume: isVolume,
                baseUrl: baseUrl,
                bookUrl: bookUrl,
                index: index,
                isVip: isVip,
                isPay: isPay,
                resourceUrl: resourceUrl,
                tag: tag,
                wordCount: wordCount,
                start: start,
                end: end,
                startFragmentId: startFragmentId,
                endFragmentId: endFragmentId,
                variable: variable,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChaptersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChaptersTable,
      BookChapter,
      $$ChaptersTableFilterComposer,
      $$ChaptersTableOrderingComposer,
      $$ChaptersTableAnnotationComposer,
      $$ChaptersTableCreateCompanionBuilder,
      $$ChaptersTableUpdateCompanionBuilder,
      (BookChapter, BaseReferences<_$AppDatabase, $ChaptersTable, BookChapter>),
      BookChapter,
      PrefetchHooks Function()
    >;
typedef $$ReaderChapterContentsTableCreateCompanionBuilder =
    ReaderChapterContentsCompanion Function({
      required String contentKey,
      required String origin,
      required String bookUrl,
      required String chapterUrl,
      required int chapterIndex,
      Value<String?> content,
      Value<int> status,
      Value<String?> failureMessage,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$ReaderChapterContentsTableUpdateCompanionBuilder =
    ReaderChapterContentsCompanion Function({
      Value<String> contentKey,
      Value<String> origin,
      Value<String> bookUrl,
      Value<String> chapterUrl,
      Value<int> chapterIndex,
      Value<String?> content,
      Value<int> status,
      Value<String?> failureMessage,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$ReaderChapterContentsTableFilterComposer
    extends Composer<_$AppDatabase, $ReaderChapterContentsTable> {
  $$ReaderChapterContentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get contentKey => $composableBuilder(
    column: $table.contentKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterUrl => $composableBuilder(
    column: $table.chapterUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureMessage => $composableBuilder(
    column: $table.failureMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReaderChapterContentsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReaderChapterContentsTable> {
  $$ReaderChapterContentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get contentKey => $composableBuilder(
    column: $table.contentKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterUrl => $composableBuilder(
    column: $table.chapterUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureMessage => $composableBuilder(
    column: $table.failureMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReaderChapterContentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReaderChapterContentsTable> {
  $$ReaderChapterContentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get contentKey => $composableBuilder(
    column: $table.contentKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get bookUrl =>
      $composableBuilder(column: $table.bookUrl, builder: (column) => column);

  GeneratedColumn<String> get chapterUrl => $composableBuilder(
    column: $table.chapterUrl,
    builder: (column) => column,
  );

  GeneratedColumn<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get failureMessage => $composableBuilder(
    column: $table.failureMessage,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ReaderChapterContentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReaderChapterContentsTable,
          ReaderChapterContent,
          $$ReaderChapterContentsTableFilterComposer,
          $$ReaderChapterContentsTableOrderingComposer,
          $$ReaderChapterContentsTableAnnotationComposer,
          $$ReaderChapterContentsTableCreateCompanionBuilder,
          $$ReaderChapterContentsTableUpdateCompanionBuilder,
          (
            ReaderChapterContent,
            BaseReferences<
              _$AppDatabase,
              $ReaderChapterContentsTable,
              ReaderChapterContent
            >,
          ),
          ReaderChapterContent,
          PrefetchHooks Function()
        > {
  $$ReaderChapterContentsTableTableManager(
    _$AppDatabase db,
    $ReaderChapterContentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$ReaderChapterContentsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$ReaderChapterContentsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$ReaderChapterContentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> contentKey = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String> bookUrl = const Value.absent(),
                Value<String> chapterUrl = const Value.absent(),
                Value<int> chapterIndex = const Value.absent(),
                Value<String?> content = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<String?> failureMessage = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReaderChapterContentsCompanion(
                contentKey: contentKey,
                origin: origin,
                bookUrl: bookUrl,
                chapterUrl: chapterUrl,
                chapterIndex: chapterIndex,
                content: content,
                status: status,
                failureMessage: failureMessage,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String contentKey,
                required String origin,
                required String bookUrl,
                required String chapterUrl,
                required int chapterIndex,
                Value<String?> content = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<String?> failureMessage = const Value.absent(),
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReaderChapterContentsCompanion.insert(
                contentKey: contentKey,
                origin: origin,
                bookUrl: bookUrl,
                chapterUrl: chapterUrl,
                chapterIndex: chapterIndex,
                content: content,
                status: status,
                failureMessage: failureMessage,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReaderChapterContentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReaderChapterContentsTable,
      ReaderChapterContent,
      $$ReaderChapterContentsTableFilterComposer,
      $$ReaderChapterContentsTableOrderingComposer,
      $$ReaderChapterContentsTableAnnotationComposer,
      $$ReaderChapterContentsTableCreateCompanionBuilder,
      $$ReaderChapterContentsTableUpdateCompanionBuilder,
      (
        ReaderChapterContent,
        BaseReferences<
          _$AppDatabase,
          $ReaderChapterContentsTable,
          ReaderChapterContent
        >,
      ),
      ReaderChapterContent,
      PrefetchHooks Function()
    >;
typedef $$BookSourcesTableCreateCompanionBuilder =
    BookSourcesCompanion Function({
      required String bookSourceUrl,
      required String bookSourceName,
      Value<int> bookSourceType,
      Value<String?> bookSourceGroup,
      Value<String?> bookSourceComment,
      Value<String?> loginUrl,
      Value<String?> loginUi,
      Value<String?> loginCheckJs,
      Value<String?> coverDecodeJs,
      Value<String?> bookUrlPattern,
      Value<String?> header,
      Value<String?> variableComment,
      Value<int> customOrder,
      Value<int> weight,
      Value<bool> enabled,
      Value<bool> enabledExplore,
      Value<bool> enabledCookieJar,
      Value<int> lastUpdateTime,
      Value<int> respondTime,
      Value<String?> jsLib,
      Value<String?> concurrentRate,
      Value<String?> exploreUrl,
      Value<String?> exploreScreen,
      Value<String?> searchUrl,
      Value<SearchRule?> ruleSearch,
      Value<ExploreRule?> ruleExplore,
      Value<BookInfoRule?> ruleBookInfo,
      Value<TocRule?> ruleToc,
      Value<ContentRule?> ruleContent,
      Value<ReviewRule?> ruleReview,
      Value<int> rowid,
    });
typedef $$BookSourcesTableUpdateCompanionBuilder =
    BookSourcesCompanion Function({
      Value<String> bookSourceUrl,
      Value<String> bookSourceName,
      Value<int> bookSourceType,
      Value<String?> bookSourceGroup,
      Value<String?> bookSourceComment,
      Value<String?> loginUrl,
      Value<String?> loginUi,
      Value<String?> loginCheckJs,
      Value<String?> coverDecodeJs,
      Value<String?> bookUrlPattern,
      Value<String?> header,
      Value<String?> variableComment,
      Value<int> customOrder,
      Value<int> weight,
      Value<bool> enabled,
      Value<bool> enabledExplore,
      Value<bool> enabledCookieJar,
      Value<int> lastUpdateTime,
      Value<int> respondTime,
      Value<String?> jsLib,
      Value<String?> concurrentRate,
      Value<String?> exploreUrl,
      Value<String?> exploreScreen,
      Value<String?> searchUrl,
      Value<SearchRule?> ruleSearch,
      Value<ExploreRule?> ruleExplore,
      Value<BookInfoRule?> ruleBookInfo,
      Value<TocRule?> ruleToc,
      Value<ContentRule?> ruleContent,
      Value<ReviewRule?> ruleReview,
      Value<int> rowid,
    });

class $$BookSourcesTableFilterComposer
    extends Composer<_$AppDatabase, $BookSourcesTable> {
  $$BookSourcesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookSourceUrl => $composableBuilder(
    column: $table.bookSourceUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookSourceName => $composableBuilder(
    column: $table.bookSourceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bookSourceType => $composableBuilder(
    column: $table.bookSourceType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookSourceGroup => $composableBuilder(
    column: $table.bookSourceGroup,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookSourceComment => $composableBuilder(
    column: $table.bookSourceComment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get loginUrl => $composableBuilder(
    column: $table.loginUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get loginUi => $composableBuilder(
    column: $table.loginUi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get loginCheckJs => $composableBuilder(
    column: $table.loginCheckJs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverDecodeJs => $composableBuilder(
    column: $table.coverDecodeJs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookUrlPattern => $composableBuilder(
    column: $table.bookUrlPattern,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get header => $composableBuilder(
    column: $table.header,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get variableComment => $composableBuilder(
    column: $table.variableComment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get customOrder => $composableBuilder(
    column: $table.customOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabledExplore => $composableBuilder(
    column: $table.enabledExplore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabledCookieJar => $composableBuilder(
    column: $table.enabledCookieJar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastUpdateTime => $composableBuilder(
    column: $table.lastUpdateTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get respondTime => $composableBuilder(
    column: $table.respondTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jsLib => $composableBuilder(
    column: $table.jsLib,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get concurrentRate => $composableBuilder(
    column: $table.concurrentRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exploreUrl => $composableBuilder(
    column: $table.exploreUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exploreScreen => $composableBuilder(
    column: $table.exploreScreen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get searchUrl => $composableBuilder(
    column: $table.searchUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SearchRule?, SearchRule, String>
  get ruleSearch => $composableBuilder(
    column: $table.ruleSearch,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<ExploreRule?, ExploreRule, String>
  get ruleExplore => $composableBuilder(
    column: $table.ruleExplore,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<BookInfoRule?, BookInfoRule, String>
  get ruleBookInfo => $composableBuilder(
    column: $table.ruleBookInfo,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<TocRule?, TocRule, String> get ruleToc =>
      $composableBuilder(
        column: $table.ruleToc,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<ContentRule?, ContentRule, String>
  get ruleContent => $composableBuilder(
    column: $table.ruleContent,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<ReviewRule?, ReviewRule, String>
  get ruleReview => $composableBuilder(
    column: $table.ruleReview,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );
}

class $$BookSourcesTableOrderingComposer
    extends Composer<_$AppDatabase, $BookSourcesTable> {
  $$BookSourcesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookSourceUrl => $composableBuilder(
    column: $table.bookSourceUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookSourceName => $composableBuilder(
    column: $table.bookSourceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bookSourceType => $composableBuilder(
    column: $table.bookSourceType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookSourceGroup => $composableBuilder(
    column: $table.bookSourceGroup,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookSourceComment => $composableBuilder(
    column: $table.bookSourceComment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get loginUrl => $composableBuilder(
    column: $table.loginUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get loginUi => $composableBuilder(
    column: $table.loginUi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get loginCheckJs => $composableBuilder(
    column: $table.loginCheckJs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverDecodeJs => $composableBuilder(
    column: $table.coverDecodeJs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookUrlPattern => $composableBuilder(
    column: $table.bookUrlPattern,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get header => $composableBuilder(
    column: $table.header,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get variableComment => $composableBuilder(
    column: $table.variableComment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get customOrder => $composableBuilder(
    column: $table.customOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabledExplore => $composableBuilder(
    column: $table.enabledExplore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabledCookieJar => $composableBuilder(
    column: $table.enabledCookieJar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastUpdateTime => $composableBuilder(
    column: $table.lastUpdateTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get respondTime => $composableBuilder(
    column: $table.respondTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jsLib => $composableBuilder(
    column: $table.jsLib,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get concurrentRate => $composableBuilder(
    column: $table.concurrentRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exploreUrl => $composableBuilder(
    column: $table.exploreUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exploreScreen => $composableBuilder(
    column: $table.exploreScreen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get searchUrl => $composableBuilder(
    column: $table.searchUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ruleSearch => $composableBuilder(
    column: $table.ruleSearch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ruleExplore => $composableBuilder(
    column: $table.ruleExplore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ruleBookInfo => $composableBuilder(
    column: $table.ruleBookInfo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ruleToc => $composableBuilder(
    column: $table.ruleToc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ruleContent => $composableBuilder(
    column: $table.ruleContent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ruleReview => $composableBuilder(
    column: $table.ruleReview,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BookSourcesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookSourcesTable> {
  $$BookSourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookSourceUrl => $composableBuilder(
    column: $table.bookSourceUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bookSourceName => $composableBuilder(
    column: $table.bookSourceName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bookSourceType => $composableBuilder(
    column: $table.bookSourceType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bookSourceGroup => $composableBuilder(
    column: $table.bookSourceGroup,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bookSourceComment => $composableBuilder(
    column: $table.bookSourceComment,
    builder: (column) => column,
  );

  GeneratedColumn<String> get loginUrl =>
      $composableBuilder(column: $table.loginUrl, builder: (column) => column);

  GeneratedColumn<String> get loginUi =>
      $composableBuilder(column: $table.loginUi, builder: (column) => column);

  GeneratedColumn<String> get loginCheckJs => $composableBuilder(
    column: $table.loginCheckJs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coverDecodeJs => $composableBuilder(
    column: $table.coverDecodeJs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bookUrlPattern => $composableBuilder(
    column: $table.bookUrlPattern,
    builder: (column) => column,
  );

  GeneratedColumn<String> get header =>
      $composableBuilder(column: $table.header, builder: (column) => column);

  GeneratedColumn<String> get variableComment => $composableBuilder(
    column: $table.variableComment,
    builder: (column) => column,
  );

  GeneratedColumn<int> get customOrder => $composableBuilder(
    column: $table.customOrder,
    builder: (column) => column,
  );

  GeneratedColumn<int> get weight =>
      $composableBuilder(column: $table.weight, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<bool> get enabledExplore => $composableBuilder(
    column: $table.enabledExplore,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enabledCookieJar => $composableBuilder(
    column: $table.enabledCookieJar,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastUpdateTime => $composableBuilder(
    column: $table.lastUpdateTime,
    builder: (column) => column,
  );

  GeneratedColumn<int> get respondTime => $composableBuilder(
    column: $table.respondTime,
    builder: (column) => column,
  );

  GeneratedColumn<String> get jsLib =>
      $composableBuilder(column: $table.jsLib, builder: (column) => column);

  GeneratedColumn<String> get concurrentRate => $composableBuilder(
    column: $table.concurrentRate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get exploreUrl => $composableBuilder(
    column: $table.exploreUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get exploreScreen => $composableBuilder(
    column: $table.exploreScreen,
    builder: (column) => column,
  );

  GeneratedColumn<String> get searchUrl =>
      $composableBuilder(column: $table.searchUrl, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SearchRule?, String> get ruleSearch =>
      $composableBuilder(
        column: $table.ruleSearch,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<ExploreRule?, String> get ruleExplore =>
      $composableBuilder(
        column: $table.ruleExplore,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<BookInfoRule?, String> get ruleBookInfo =>
      $composableBuilder(
        column: $table.ruleBookInfo,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<TocRule?, String> get ruleToc =>
      $composableBuilder(column: $table.ruleToc, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ContentRule?, String> get ruleContent =>
      $composableBuilder(
        column: $table.ruleContent,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<ReviewRule?, String> get ruleReview =>
      $composableBuilder(
        column: $table.ruleReview,
        builder: (column) => column,
      );
}

class $$BookSourcesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookSourcesTable,
          BookSource,
          $$BookSourcesTableFilterComposer,
          $$BookSourcesTableOrderingComposer,
          $$BookSourcesTableAnnotationComposer,
          $$BookSourcesTableCreateCompanionBuilder,
          $$BookSourcesTableUpdateCompanionBuilder,
          (
            BookSource,
            BaseReferences<_$AppDatabase, $BookSourcesTable, BookSource>,
          ),
          BookSource,
          PrefetchHooks Function()
        > {
  $$BookSourcesTableTableManager(_$AppDatabase db, $BookSourcesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$BookSourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$BookSourcesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () =>
                  $$BookSourcesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookSourceUrl = const Value.absent(),
                Value<String> bookSourceName = const Value.absent(),
                Value<int> bookSourceType = const Value.absent(),
                Value<String?> bookSourceGroup = const Value.absent(),
                Value<String?> bookSourceComment = const Value.absent(),
                Value<String?> loginUrl = const Value.absent(),
                Value<String?> loginUi = const Value.absent(),
                Value<String?> loginCheckJs = const Value.absent(),
                Value<String?> coverDecodeJs = const Value.absent(),
                Value<String?> bookUrlPattern = const Value.absent(),
                Value<String?> header = const Value.absent(),
                Value<String?> variableComment = const Value.absent(),
                Value<int> customOrder = const Value.absent(),
                Value<int> weight = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<bool> enabledExplore = const Value.absent(),
                Value<bool> enabledCookieJar = const Value.absent(),
                Value<int> lastUpdateTime = const Value.absent(),
                Value<int> respondTime = const Value.absent(),
                Value<String?> jsLib = const Value.absent(),
                Value<String?> concurrentRate = const Value.absent(),
                Value<String?> exploreUrl = const Value.absent(),
                Value<String?> exploreScreen = const Value.absent(),
                Value<String?> searchUrl = const Value.absent(),
                Value<SearchRule?> ruleSearch = const Value.absent(),
                Value<ExploreRule?> ruleExplore = const Value.absent(),
                Value<BookInfoRule?> ruleBookInfo = const Value.absent(),
                Value<TocRule?> ruleToc = const Value.absent(),
                Value<ContentRule?> ruleContent = const Value.absent(),
                Value<ReviewRule?> ruleReview = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookSourcesCompanion(
                bookSourceUrl: bookSourceUrl,
                bookSourceName: bookSourceName,
                bookSourceType: bookSourceType,
                bookSourceGroup: bookSourceGroup,
                bookSourceComment: bookSourceComment,
                loginUrl: loginUrl,
                loginUi: loginUi,
                loginCheckJs: loginCheckJs,
                coverDecodeJs: coverDecodeJs,
                bookUrlPattern: bookUrlPattern,
                header: header,
                variableComment: variableComment,
                customOrder: customOrder,
                weight: weight,
                enabled: enabled,
                enabledExplore: enabledExplore,
                enabledCookieJar: enabledCookieJar,
                lastUpdateTime: lastUpdateTime,
                respondTime: respondTime,
                jsLib: jsLib,
                concurrentRate: concurrentRate,
                exploreUrl: exploreUrl,
                exploreScreen: exploreScreen,
                searchUrl: searchUrl,
                ruleSearch: ruleSearch,
                ruleExplore: ruleExplore,
                ruleBookInfo: ruleBookInfo,
                ruleToc: ruleToc,
                ruleContent: ruleContent,
                ruleReview: ruleReview,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookSourceUrl,
                required String bookSourceName,
                Value<int> bookSourceType = const Value.absent(),
                Value<String?> bookSourceGroup = const Value.absent(),
                Value<String?> bookSourceComment = const Value.absent(),
                Value<String?> loginUrl = const Value.absent(),
                Value<String?> loginUi = const Value.absent(),
                Value<String?> loginCheckJs = const Value.absent(),
                Value<String?> coverDecodeJs = const Value.absent(),
                Value<String?> bookUrlPattern = const Value.absent(),
                Value<String?> header = const Value.absent(),
                Value<String?> variableComment = const Value.absent(),
                Value<int> customOrder = const Value.absent(),
                Value<int> weight = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<bool> enabledExplore = const Value.absent(),
                Value<bool> enabledCookieJar = const Value.absent(),
                Value<int> lastUpdateTime = const Value.absent(),
                Value<int> respondTime = const Value.absent(),
                Value<String?> jsLib = const Value.absent(),
                Value<String?> concurrentRate = const Value.absent(),
                Value<String?> exploreUrl = const Value.absent(),
                Value<String?> exploreScreen = const Value.absent(),
                Value<String?> searchUrl = const Value.absent(),
                Value<SearchRule?> ruleSearch = const Value.absent(),
                Value<ExploreRule?> ruleExplore = const Value.absent(),
                Value<BookInfoRule?> ruleBookInfo = const Value.absent(),
                Value<TocRule?> ruleToc = const Value.absent(),
                Value<ContentRule?> ruleContent = const Value.absent(),
                Value<ReviewRule?> ruleReview = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookSourcesCompanion.insert(
                bookSourceUrl: bookSourceUrl,
                bookSourceName: bookSourceName,
                bookSourceType: bookSourceType,
                bookSourceGroup: bookSourceGroup,
                bookSourceComment: bookSourceComment,
                loginUrl: loginUrl,
                loginUi: loginUi,
                loginCheckJs: loginCheckJs,
                coverDecodeJs: coverDecodeJs,
                bookUrlPattern: bookUrlPattern,
                header: header,
                variableComment: variableComment,
                customOrder: customOrder,
                weight: weight,
                enabled: enabled,
                enabledExplore: enabledExplore,
                enabledCookieJar: enabledCookieJar,
                lastUpdateTime: lastUpdateTime,
                respondTime: respondTime,
                jsLib: jsLib,
                concurrentRate: concurrentRate,
                exploreUrl: exploreUrl,
                exploreScreen: exploreScreen,
                searchUrl: searchUrl,
                ruleSearch: ruleSearch,
                ruleExplore: ruleExplore,
                ruleBookInfo: ruleBookInfo,
                ruleToc: ruleToc,
                ruleContent: ruleContent,
                ruleReview: ruleReview,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BookSourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookSourcesTable,
      BookSource,
      $$BookSourcesTableFilterComposer,
      $$BookSourcesTableOrderingComposer,
      $$BookSourcesTableAnnotationComposer,
      $$BookSourcesTableCreateCompanionBuilder,
      $$BookSourcesTableUpdateCompanionBuilder,
      (
        BookSource,
        BaseReferences<_$AppDatabase, $BookSourcesTable, BookSource>,
      ),
      BookSource,
      PrefetchHooks Function()
    >;
typedef $$BookGroupsTableCreateCompanionBuilder =
    BookGroupsCompanion Function({
      Value<int> groupId,
      required String groupName,
      Value<int> order,
      Value<bool> show,
      Value<String?> coverPath,
      Value<bool> enableRefresh,
      Value<int> bookSort,
    });
typedef $$BookGroupsTableUpdateCompanionBuilder =
    BookGroupsCompanion Function({
      Value<int> groupId,
      Value<String> groupName,
      Value<int> order,
      Value<bool> show,
      Value<String?> coverPath,
      Value<bool> enableRefresh,
      Value<int> bookSort,
    });

class $$BookGroupsTableFilterComposer
    extends Composer<_$AppDatabase, $BookGroupsTable> {
  $$BookGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get order => $composableBuilder(
    column: $table.order,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get show => $composableBuilder(
    column: $table.show,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enableRefresh => $composableBuilder(
    column: $table.enableRefresh,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bookSort => $composableBuilder(
    column: $table.bookSort,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BookGroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $BookGroupsTable> {
  $$BookGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get order => $composableBuilder(
    column: $table.order,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get show => $composableBuilder(
    column: $table.show,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enableRefresh => $composableBuilder(
    column: $table.enableRefresh,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bookSort => $composableBuilder(
    column: $table.bookSort,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BookGroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookGroupsTable> {
  $$BookGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get groupName =>
      $composableBuilder(column: $table.groupName, builder: (column) => column);

  GeneratedColumn<int> get order =>
      $composableBuilder(column: $table.order, builder: (column) => column);

  GeneratedColumn<bool> get show =>
      $composableBuilder(column: $table.show, builder: (column) => column);

  GeneratedColumn<String> get coverPath =>
      $composableBuilder(column: $table.coverPath, builder: (column) => column);

  GeneratedColumn<bool> get enableRefresh => $composableBuilder(
    column: $table.enableRefresh,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bookSort =>
      $composableBuilder(column: $table.bookSort, builder: (column) => column);
}

class $$BookGroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookGroupsTable,
          BookGroup,
          $$BookGroupsTableFilterComposer,
          $$BookGroupsTableOrderingComposer,
          $$BookGroupsTableAnnotationComposer,
          $$BookGroupsTableCreateCompanionBuilder,
          $$BookGroupsTableUpdateCompanionBuilder,
          (
            BookGroup,
            BaseReferences<_$AppDatabase, $BookGroupsTable, BookGroup>,
          ),
          BookGroup,
          PrefetchHooks Function()
        > {
  $$BookGroupsTableTableManager(_$AppDatabase db, $BookGroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$BookGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$BookGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$BookGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> groupId = const Value.absent(),
                Value<String> groupName = const Value.absent(),
                Value<int> order = const Value.absent(),
                Value<bool> show = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<bool> enableRefresh = const Value.absent(),
                Value<int> bookSort = const Value.absent(),
              }) => BookGroupsCompanion(
                groupId: groupId,
                groupName: groupName,
                order: order,
                show: show,
                coverPath: coverPath,
                enableRefresh: enableRefresh,
                bookSort: bookSort,
              ),
          createCompanionCallback:
              ({
                Value<int> groupId = const Value.absent(),
                required String groupName,
                Value<int> order = const Value.absent(),
                Value<bool> show = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<bool> enableRefresh = const Value.absent(),
                Value<int> bookSort = const Value.absent(),
              }) => BookGroupsCompanion.insert(
                groupId: groupId,
                groupName: groupName,
                order: order,
                show: show,
                coverPath: coverPath,
                enableRefresh: enableRefresh,
                bookSort: bookSort,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BookGroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookGroupsTable,
      BookGroup,
      $$BookGroupsTableFilterComposer,
      $$BookGroupsTableOrderingComposer,
      $$BookGroupsTableAnnotationComposer,
      $$BookGroupsTableCreateCompanionBuilder,
      $$BookGroupsTableUpdateCompanionBuilder,
      (BookGroup, BaseReferences<_$AppDatabase, $BookGroupsTable, BookGroup>),
      BookGroup,
      PrefetchHooks Function()
    >;
typedef $$SearchHistoryTableTableCreateCompanionBuilder =
    SearchHistoryTableCompanion Function({
      Value<int> id,
      required String keyword,
      required int searchTime,
    });
typedef $$SearchHistoryTableTableUpdateCompanionBuilder =
    SearchHistoryTableCompanion Function({
      Value<int> id,
      Value<String> keyword,
      Value<int> searchTime,
    });

class $$SearchHistoryTableTableFilterComposer
    extends Composer<_$AppDatabase, $SearchHistoryTableTable> {
  $$SearchHistoryTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get keyword => $composableBuilder(
    column: $table.keyword,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get searchTime => $composableBuilder(
    column: $table.searchTime,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SearchHistoryTableTableOrderingComposer
    extends Composer<_$AppDatabase, $SearchHistoryTableTable> {
  $$SearchHistoryTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keyword => $composableBuilder(
    column: $table.keyword,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get searchTime => $composableBuilder(
    column: $table.searchTime,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SearchHistoryTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $SearchHistoryTableTable> {
  $$SearchHistoryTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get keyword =>
      $composableBuilder(column: $table.keyword, builder: (column) => column);

  GeneratedColumn<int> get searchTime => $composableBuilder(
    column: $table.searchTime,
    builder: (column) => column,
  );
}

class $$SearchHistoryTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SearchHistoryTableTable,
          SearchHistoryRow,
          $$SearchHistoryTableTableFilterComposer,
          $$SearchHistoryTableTableOrderingComposer,
          $$SearchHistoryTableTableAnnotationComposer,
          $$SearchHistoryTableTableCreateCompanionBuilder,
          $$SearchHistoryTableTableUpdateCompanionBuilder,
          (
            SearchHistoryRow,
            BaseReferences<
              _$AppDatabase,
              $SearchHistoryTableTable,
              SearchHistoryRow
            >,
          ),
          SearchHistoryRow,
          PrefetchHooks Function()
        > {
  $$SearchHistoryTableTableTableManager(
    _$AppDatabase db,
    $SearchHistoryTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$SearchHistoryTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$SearchHistoryTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$SearchHistoryTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> keyword = const Value.absent(),
                Value<int> searchTime = const Value.absent(),
              }) => SearchHistoryTableCompanion(
                id: id,
                keyword: keyword,
                searchTime: searchTime,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String keyword,
                required int searchTime,
              }) => SearchHistoryTableCompanion.insert(
                id: id,
                keyword: keyword,
                searchTime: searchTime,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SearchHistoryTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SearchHistoryTableTable,
      SearchHistoryRow,
      $$SearchHistoryTableTableFilterComposer,
      $$SearchHistoryTableTableOrderingComposer,
      $$SearchHistoryTableTableAnnotationComposer,
      $$SearchHistoryTableTableCreateCompanionBuilder,
      $$SearchHistoryTableTableUpdateCompanionBuilder,
      (
        SearchHistoryRow,
        BaseReferences<
          _$AppDatabase,
          $SearchHistoryTableTable,
          SearchHistoryRow
        >,
      ),
      SearchHistoryRow,
      PrefetchHooks Function()
    >;
typedef $$ReplaceRulesTableCreateCompanionBuilder =
    ReplaceRulesCompanion Function({
      Value<int> id,
      Value<String> name,
      required String pattern,
      Value<String> replacement,
      Value<String?> scope,
      Value<bool> scopeTitle,
      Value<bool> scopeContent,
      Value<String?> excludeScope,
      Value<bool> isEnabled,
      Value<bool> isRegex,
      Value<int> timeoutMillisecond,
      Value<String?> group,
      Value<int> order,
    });
typedef $$ReplaceRulesTableUpdateCompanionBuilder =
    ReplaceRulesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> pattern,
      Value<String> replacement,
      Value<String?> scope,
      Value<bool> scopeTitle,
      Value<bool> scopeContent,
      Value<String?> excludeScope,
      Value<bool> isEnabled,
      Value<bool> isRegex,
      Value<int> timeoutMillisecond,
      Value<String?> group,
      Value<int> order,
    });

class $$ReplaceRulesTableFilterComposer
    extends Composer<_$AppDatabase, $ReplaceRulesTable> {
  $$ReplaceRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<String, String, String> get name =>
      $composableBuilder(
        column: $table.name,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get pattern => $composableBuilder(
    column: $table.pattern,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<String, String, String> get replacement =>
      $composableBuilder(
        column: $table.replacement,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get scopeTitle => $composableBuilder(
    column: $table.scopeTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get scopeContent => $composableBuilder(
    column: $table.scopeContent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get excludeScope => $composableBuilder(
    column: $table.excludeScope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isEnabled => $composableBuilder(
    column: $table.isEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRegex => $composableBuilder(
    column: $table.isRegex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timeoutMillisecond => $composableBuilder(
    column: $table.timeoutMillisecond,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get group => $composableBuilder(
    column: $table.group,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get order => $composableBuilder(
    column: $table.order,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReplaceRulesTableOrderingComposer
    extends Composer<_$AppDatabase, $ReplaceRulesTable> {
  $$ReplaceRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pattern => $composableBuilder(
    column: $table.pattern,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replacement => $composableBuilder(
    column: $table.replacement,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get scopeTitle => $composableBuilder(
    column: $table.scopeTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get scopeContent => $composableBuilder(
    column: $table.scopeContent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get excludeScope => $composableBuilder(
    column: $table.excludeScope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isEnabled => $composableBuilder(
    column: $table.isEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRegex => $composableBuilder(
    column: $table.isRegex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timeoutMillisecond => $composableBuilder(
    column: $table.timeoutMillisecond,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get group => $composableBuilder(
    column: $table.group,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get order => $composableBuilder(
    column: $table.order,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReplaceRulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReplaceRulesTable> {
  $$ReplaceRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<String, String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get pattern =>
      $composableBuilder(column: $table.pattern, builder: (column) => column);

  GeneratedColumnWithTypeConverter<String, String> get replacement =>
      $composableBuilder(
        column: $table.replacement,
        builder: (column) => column,
      );

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<bool> get scopeTitle => $composableBuilder(
    column: $table.scopeTitle,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get scopeContent => $composableBuilder(
    column: $table.scopeContent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get excludeScope => $composableBuilder(
    column: $table.excludeScope,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isEnabled =>
      $composableBuilder(column: $table.isEnabled, builder: (column) => column);

  GeneratedColumn<bool> get isRegex =>
      $composableBuilder(column: $table.isRegex, builder: (column) => column);

  GeneratedColumn<int> get timeoutMillisecond => $composableBuilder(
    column: $table.timeoutMillisecond,
    builder: (column) => column,
  );

  GeneratedColumn<String> get group =>
      $composableBuilder(column: $table.group, builder: (column) => column);

  GeneratedColumn<int> get order =>
      $composableBuilder(column: $table.order, builder: (column) => column);
}

class $$ReplaceRulesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReplaceRulesTable,
          ReplaceRule,
          $$ReplaceRulesTableFilterComposer,
          $$ReplaceRulesTableOrderingComposer,
          $$ReplaceRulesTableAnnotationComposer,
          $$ReplaceRulesTableCreateCompanionBuilder,
          $$ReplaceRulesTableUpdateCompanionBuilder,
          (
            ReplaceRule,
            BaseReferences<_$AppDatabase, $ReplaceRulesTable, ReplaceRule>,
          ),
          ReplaceRule,
          PrefetchHooks Function()
        > {
  $$ReplaceRulesTableTableManager(_$AppDatabase db, $ReplaceRulesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$ReplaceRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$ReplaceRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () =>
                  $$ReplaceRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> pattern = const Value.absent(),
                Value<String> replacement = const Value.absent(),
                Value<String?> scope = const Value.absent(),
                Value<bool> scopeTitle = const Value.absent(),
                Value<bool> scopeContent = const Value.absent(),
                Value<String?> excludeScope = const Value.absent(),
                Value<bool> isEnabled = const Value.absent(),
                Value<bool> isRegex = const Value.absent(),
                Value<int> timeoutMillisecond = const Value.absent(),
                Value<String?> group = const Value.absent(),
                Value<int> order = const Value.absent(),
              }) => ReplaceRulesCompanion(
                id: id,
                name: name,
                pattern: pattern,
                replacement: replacement,
                scope: scope,
                scopeTitle: scopeTitle,
                scopeContent: scopeContent,
                excludeScope: excludeScope,
                isEnabled: isEnabled,
                isRegex: isRegex,
                timeoutMillisecond: timeoutMillisecond,
                group: group,
                order: order,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                required String pattern,
                Value<String> replacement = const Value.absent(),
                Value<String?> scope = const Value.absent(),
                Value<bool> scopeTitle = const Value.absent(),
                Value<bool> scopeContent = const Value.absent(),
                Value<String?> excludeScope = const Value.absent(),
                Value<bool> isEnabled = const Value.absent(),
                Value<bool> isRegex = const Value.absent(),
                Value<int> timeoutMillisecond = const Value.absent(),
                Value<String?> group = const Value.absent(),
                Value<int> order = const Value.absent(),
              }) => ReplaceRulesCompanion.insert(
                id: id,
                name: name,
                pattern: pattern,
                replacement: replacement,
                scope: scope,
                scopeTitle: scopeTitle,
                scopeContent: scopeContent,
                excludeScope: excludeScope,
                isEnabled: isEnabled,
                isRegex: isRegex,
                timeoutMillisecond: timeoutMillisecond,
                group: group,
                order: order,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReplaceRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReplaceRulesTable,
      ReplaceRule,
      $$ReplaceRulesTableFilterComposer,
      $$ReplaceRulesTableOrderingComposer,
      $$ReplaceRulesTableAnnotationComposer,
      $$ReplaceRulesTableCreateCompanionBuilder,
      $$ReplaceRulesTableUpdateCompanionBuilder,
      (
        ReplaceRule,
        BaseReferences<_$AppDatabase, $ReplaceRulesTable, ReplaceRule>,
      ),
      ReplaceRule,
      PrefetchHooks Function()
    >;
typedef $$BookmarksTableCreateCompanionBuilder =
    BookmarksCompanion Function({
      Value<int> id,
      required int time,
      required String bookName,
      Value<String> bookAuthor,
      Value<int> chapterIndex,
      Value<int> chapterPos,
      Value<String> chapterName,
      required String bookUrl,
      Value<String> bookText,
      Value<String> content,
    });
typedef $$BookmarksTableUpdateCompanionBuilder =
    BookmarksCompanion Function({
      Value<int> id,
      Value<int> time,
      Value<String> bookName,
      Value<String> bookAuthor,
      Value<int> chapterIndex,
      Value<int> chapterPos,
      Value<String> chapterName,
      Value<String> bookUrl,
      Value<String> bookText,
      Value<String> content,
    });

class $$BookmarksTableFilterComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get time => $composableBuilder(
    column: $table.time,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookName => $composableBuilder(
    column: $table.bookName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<String, String, String> get bookAuthor =>
      $composableBuilder(
        column: $table.bookAuthor,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterPos => $composableBuilder(
    column: $table.chapterPos,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<String, String, String> get chapterName =>
      $composableBuilder(
        column: $table.chapterName,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<String, String, String> get bookText =>
      $composableBuilder(
        column: $table.bookText,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<String, String, String> get content =>
      $composableBuilder(
        column: $table.content,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$BookmarksTableOrderingComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get time => $composableBuilder(
    column: $table.time,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookName => $composableBuilder(
    column: $table.bookName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookAuthor => $composableBuilder(
    column: $table.bookAuthor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterPos => $composableBuilder(
    column: $table.chapterPos,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterName => $composableBuilder(
    column: $table.chapterName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookText => $composableBuilder(
    column: $table.bookText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BookmarksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get time =>
      $composableBuilder(column: $table.time, builder: (column) => column);

  GeneratedColumn<String> get bookName =>
      $composableBuilder(column: $table.bookName, builder: (column) => column);

  GeneratedColumnWithTypeConverter<String, String> get bookAuthor =>
      $composableBuilder(
        column: $table.bookAuthor,
        builder: (column) => column,
      );

  GeneratedColumn<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get chapterPos => $composableBuilder(
    column: $table.chapterPos,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<String, String> get chapterName =>
      $composableBuilder(
        column: $table.chapterName,
        builder: (column) => column,
      );

  GeneratedColumn<String> get bookUrl =>
      $composableBuilder(column: $table.bookUrl, builder: (column) => column);

  GeneratedColumnWithTypeConverter<String, String> get bookText =>
      $composableBuilder(column: $table.bookText, builder: (column) => column);

  GeneratedColumnWithTypeConverter<String, String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);
}

class $$BookmarksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookmarksTable,
          Bookmark,
          $$BookmarksTableFilterComposer,
          $$BookmarksTableOrderingComposer,
          $$BookmarksTableAnnotationComposer,
          $$BookmarksTableCreateCompanionBuilder,
          $$BookmarksTableUpdateCompanionBuilder,
          (Bookmark, BaseReferences<_$AppDatabase, $BookmarksTable, Bookmark>),
          Bookmark,
          PrefetchHooks Function()
        > {
  $$BookmarksTableTableManager(_$AppDatabase db, $BookmarksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$BookmarksTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$BookmarksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$BookmarksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> time = const Value.absent(),
                Value<String> bookName = const Value.absent(),
                Value<String> bookAuthor = const Value.absent(),
                Value<int> chapterIndex = const Value.absent(),
                Value<int> chapterPos = const Value.absent(),
                Value<String> chapterName = const Value.absent(),
                Value<String> bookUrl = const Value.absent(),
                Value<String> bookText = const Value.absent(),
                Value<String> content = const Value.absent(),
              }) => BookmarksCompanion(
                id: id,
                time: time,
                bookName: bookName,
                bookAuthor: bookAuthor,
                chapterIndex: chapterIndex,
                chapterPos: chapterPos,
                chapterName: chapterName,
                bookUrl: bookUrl,
                bookText: bookText,
                content: content,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int time,
                required String bookName,
                Value<String> bookAuthor = const Value.absent(),
                Value<int> chapterIndex = const Value.absent(),
                Value<int> chapterPos = const Value.absent(),
                Value<String> chapterName = const Value.absent(),
                required String bookUrl,
                Value<String> bookText = const Value.absent(),
                Value<String> content = const Value.absent(),
              }) => BookmarksCompanion.insert(
                id: id,
                time: time,
                bookName: bookName,
                bookAuthor: bookAuthor,
                chapterIndex: chapterIndex,
                chapterPos: chapterPos,
                chapterName: chapterName,
                bookUrl: bookUrl,
                bookText: bookText,
                content: content,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BookmarksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookmarksTable,
      Bookmark,
      $$BookmarksTableFilterComposer,
      $$BookmarksTableOrderingComposer,
      $$BookmarksTableAnnotationComposer,
      $$BookmarksTableCreateCompanionBuilder,
      $$BookmarksTableUpdateCompanionBuilder,
      (Bookmark, BaseReferences<_$AppDatabase, $BookmarksTable, Bookmark>),
      Bookmark,
      PrefetchHooks Function()
    >;
typedef $$CookiesTableCreateCompanionBuilder =
    CookiesCompanion Function({
      required String url,
      required String cookie,
      Value<int> rowid,
    });
typedef $$CookiesTableUpdateCompanionBuilder =
    CookiesCompanion Function({
      Value<String> url,
      Value<String> cookie,
      Value<int> rowid,
    });

class $$CookiesTableFilterComposer
    extends Composer<_$AppDatabase, $CookiesTable> {
  $$CookiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cookie => $composableBuilder(
    column: $table.cookie,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CookiesTableOrderingComposer
    extends Composer<_$AppDatabase, $CookiesTable> {
  $$CookiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cookie => $composableBuilder(
    column: $table.cookie,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CookiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CookiesTable> {
  $$CookiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get cookie =>
      $composableBuilder(column: $table.cookie, builder: (column) => column);
}

class $$CookiesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CookiesTable,
          Cookie,
          $$CookiesTableFilterComposer,
          $$CookiesTableOrderingComposer,
          $$CookiesTableAnnotationComposer,
          $$CookiesTableCreateCompanionBuilder,
          $$CookiesTableUpdateCompanionBuilder,
          (Cookie, BaseReferences<_$AppDatabase, $CookiesTable, Cookie>),
          Cookie,
          PrefetchHooks Function()
        > {
  $$CookiesTableTableManager(_$AppDatabase db, $CookiesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$CookiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$CookiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$CookiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> url = const Value.absent(),
                Value<String> cookie = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CookiesCompanion(url: url, cookie: cookie, rowid: rowid),
          createCompanionCallback:
              ({
                required String url,
                required String cookie,
                Value<int> rowid = const Value.absent(),
              }) => CookiesCompanion.insert(
                url: url,
                cookie: cookie,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CookiesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CookiesTable,
      Cookie,
      $$CookiesTableFilterComposer,
      $$CookiesTableOrderingComposer,
      $$CookiesTableAnnotationComposer,
      $$CookiesTableCreateCompanionBuilder,
      $$CookiesTableUpdateCompanionBuilder,
      (Cookie, BaseReferences<_$AppDatabase, $CookiesTable, Cookie>),
      Cookie,
      PrefetchHooks Function()
    >;
typedef $$DictRulesTableCreateCompanionBuilder =
    DictRulesCompanion Function({
      Value<int> id,
      required String name,
      Value<String> urlRule,
      Value<String> showRule,
      Value<bool> enabled,
      Value<int> sortNumber,
    });
typedef $$DictRulesTableUpdateCompanionBuilder =
    DictRulesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> urlRule,
      Value<String> showRule,
      Value<bool> enabled,
      Value<int> sortNumber,
    });

class $$DictRulesTableFilterComposer
    extends Composer<_$AppDatabase, $DictRulesTable> {
  $$DictRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<String, String, String> get urlRule =>
      $composableBuilder(
        column: $table.urlRule,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<String, String, String> get showRule =>
      $composableBuilder(
        column: $table.showRule,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortNumber => $composableBuilder(
    column: $table.sortNumber,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DictRulesTableOrderingComposer
    extends Composer<_$AppDatabase, $DictRulesTable> {
  $$DictRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get urlRule => $composableBuilder(
    column: $table.urlRule,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get showRule => $composableBuilder(
    column: $table.showRule,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortNumber => $composableBuilder(
    column: $table.sortNumber,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DictRulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DictRulesTable> {
  $$DictRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumnWithTypeConverter<String, String> get urlRule =>
      $composableBuilder(column: $table.urlRule, builder: (column) => column);

  GeneratedColumnWithTypeConverter<String, String> get showRule =>
      $composableBuilder(column: $table.showRule, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get sortNumber => $composableBuilder(
    column: $table.sortNumber,
    builder: (column) => column,
  );
}

class $$DictRulesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DictRulesTable,
          DictRule,
          $$DictRulesTableFilterComposer,
          $$DictRulesTableOrderingComposer,
          $$DictRulesTableAnnotationComposer,
          $$DictRulesTableCreateCompanionBuilder,
          $$DictRulesTableUpdateCompanionBuilder,
          (DictRule, BaseReferences<_$AppDatabase, $DictRulesTable, DictRule>),
          DictRule,
          PrefetchHooks Function()
        > {
  $$DictRulesTableTableManager(_$AppDatabase db, $DictRulesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$DictRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$DictRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$DictRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> urlRule = const Value.absent(),
                Value<String> showRule = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> sortNumber = const Value.absent(),
              }) => DictRulesCompanion(
                id: id,
                name: name,
                urlRule: urlRule,
                showRule: showRule,
                enabled: enabled,
                sortNumber: sortNumber,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String> urlRule = const Value.absent(),
                Value<String> showRule = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> sortNumber = const Value.absent(),
              }) => DictRulesCompanion.insert(
                id: id,
                name: name,
                urlRule: urlRule,
                showRule: showRule,
                enabled: enabled,
                sortNumber: sortNumber,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DictRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DictRulesTable,
      DictRule,
      $$DictRulesTableFilterComposer,
      $$DictRulesTableOrderingComposer,
      $$DictRulesTableAnnotationComposer,
      $$DictRulesTableCreateCompanionBuilder,
      $$DictRulesTableUpdateCompanionBuilder,
      (DictRule, BaseReferences<_$AppDatabase, $DictRulesTable, DictRule>),
      DictRule,
      PrefetchHooks Function()
    >;
typedef $$HttpTtsTableTableCreateCompanionBuilder =
    HttpTtsTableCompanion Function({
      Value<int> id,
      required String name,
      required String url,
      Value<String?> contentType,
      Value<String?> concurrentRate,
      Value<String?> loginUrl,
      Value<String?> loginUi,
      Value<String?> header,
      Value<String?> jsLib,
      Value<bool> enabledCookieJar,
      Value<String?> loginCheckJs,
      Value<int> lastUpdateTime,
    });
typedef $$HttpTtsTableTableUpdateCompanionBuilder =
    HttpTtsTableCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> url,
      Value<String?> contentType,
      Value<String?> concurrentRate,
      Value<String?> loginUrl,
      Value<String?> loginUi,
      Value<String?> header,
      Value<String?> jsLib,
      Value<bool> enabledCookieJar,
      Value<String?> loginCheckJs,
      Value<int> lastUpdateTime,
    });

class $$HttpTtsTableTableFilterComposer
    extends Composer<_$AppDatabase, $HttpTtsTableTable> {
  $$HttpTtsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get concurrentRate => $composableBuilder(
    column: $table.concurrentRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get loginUrl => $composableBuilder(
    column: $table.loginUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get loginUi => $composableBuilder(
    column: $table.loginUi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get header => $composableBuilder(
    column: $table.header,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jsLib => $composableBuilder(
    column: $table.jsLib,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabledCookieJar => $composableBuilder(
    column: $table.enabledCookieJar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get loginCheckJs => $composableBuilder(
    column: $table.loginCheckJs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastUpdateTime => $composableBuilder(
    column: $table.lastUpdateTime,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HttpTtsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $HttpTtsTableTable> {
  $$HttpTtsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get concurrentRate => $composableBuilder(
    column: $table.concurrentRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get loginUrl => $composableBuilder(
    column: $table.loginUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get loginUi => $composableBuilder(
    column: $table.loginUi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get header => $composableBuilder(
    column: $table.header,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jsLib => $composableBuilder(
    column: $table.jsLib,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabledCookieJar => $composableBuilder(
    column: $table.enabledCookieJar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get loginCheckJs => $composableBuilder(
    column: $table.loginCheckJs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastUpdateTime => $composableBuilder(
    column: $table.lastUpdateTime,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HttpTtsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $HttpTtsTableTable> {
  $$HttpTtsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get concurrentRate => $composableBuilder(
    column: $table.concurrentRate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get loginUrl =>
      $composableBuilder(column: $table.loginUrl, builder: (column) => column);

  GeneratedColumn<String> get loginUi =>
      $composableBuilder(column: $table.loginUi, builder: (column) => column);

  GeneratedColumn<String> get header =>
      $composableBuilder(column: $table.header, builder: (column) => column);

  GeneratedColumn<String> get jsLib =>
      $composableBuilder(column: $table.jsLib, builder: (column) => column);

  GeneratedColumn<bool> get enabledCookieJar => $composableBuilder(
    column: $table.enabledCookieJar,
    builder: (column) => column,
  );

  GeneratedColumn<String> get loginCheckJs => $composableBuilder(
    column: $table.loginCheckJs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastUpdateTime => $composableBuilder(
    column: $table.lastUpdateTime,
    builder: (column) => column,
  );
}

class $$HttpTtsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HttpTtsTableTable,
          HttpTTS,
          $$HttpTtsTableTableFilterComposer,
          $$HttpTtsTableTableOrderingComposer,
          $$HttpTtsTableTableAnnotationComposer,
          $$HttpTtsTableTableCreateCompanionBuilder,
          $$HttpTtsTableTableUpdateCompanionBuilder,
          (HttpTTS, BaseReferences<_$AppDatabase, $HttpTtsTableTable, HttpTTS>),
          HttpTTS,
          PrefetchHooks Function()
        > {
  $$HttpTtsTableTableTableManager(_$AppDatabase db, $HttpTtsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$HttpTtsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$HttpTtsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () =>
                  $$HttpTtsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String?> contentType = const Value.absent(),
                Value<String?> concurrentRate = const Value.absent(),
                Value<String?> loginUrl = const Value.absent(),
                Value<String?> loginUi = const Value.absent(),
                Value<String?> header = const Value.absent(),
                Value<String?> jsLib = const Value.absent(),
                Value<bool> enabledCookieJar = const Value.absent(),
                Value<String?> loginCheckJs = const Value.absent(),
                Value<int> lastUpdateTime = const Value.absent(),
              }) => HttpTtsTableCompanion(
                id: id,
                name: name,
                url: url,
                contentType: contentType,
                concurrentRate: concurrentRate,
                loginUrl: loginUrl,
                loginUi: loginUi,
                header: header,
                jsLib: jsLib,
                enabledCookieJar: enabledCookieJar,
                loginCheckJs: loginCheckJs,
                lastUpdateTime: lastUpdateTime,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String url,
                Value<String?> contentType = const Value.absent(),
                Value<String?> concurrentRate = const Value.absent(),
                Value<String?> loginUrl = const Value.absent(),
                Value<String?> loginUi = const Value.absent(),
                Value<String?> header = const Value.absent(),
                Value<String?> jsLib = const Value.absent(),
                Value<bool> enabledCookieJar = const Value.absent(),
                Value<String?> loginCheckJs = const Value.absent(),
                Value<int> lastUpdateTime = const Value.absent(),
              }) => HttpTtsTableCompanion.insert(
                id: id,
                name: name,
                url: url,
                contentType: contentType,
                concurrentRate: concurrentRate,
                loginUrl: loginUrl,
                loginUi: loginUi,
                header: header,
                jsLib: jsLib,
                enabledCookieJar: enabledCookieJar,
                loginCheckJs: loginCheckJs,
                lastUpdateTime: lastUpdateTime,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HttpTtsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HttpTtsTableTable,
      HttpTTS,
      $$HttpTtsTableTableFilterComposer,
      $$HttpTtsTableTableOrderingComposer,
      $$HttpTtsTableTableAnnotationComposer,
      $$HttpTtsTableTableCreateCompanionBuilder,
      $$HttpTtsTableTableUpdateCompanionBuilder,
      (HttpTTS, BaseReferences<_$AppDatabase, $HttpTtsTableTable, HttpTTS>),
      HttpTTS,
      PrefetchHooks Function()
    >;
typedef $$ReadRecordsTableCreateCompanionBuilder =
    ReadRecordsCompanion Function({
      Value<int> id,
      required String bookName,
      required String deviceId,
      Value<int> readTime,
      Value<int> lastRead,
    });
typedef $$ReadRecordsTableUpdateCompanionBuilder =
    ReadRecordsCompanion Function({
      Value<int> id,
      Value<String> bookName,
      Value<String> deviceId,
      Value<int> readTime,
      Value<int> lastRead,
    });

class $$ReadRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $ReadRecordsTable> {
  $$ReadRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookName => $composableBuilder(
    column: $table.bookName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get readTime => $composableBuilder(
    column: $table.readTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastRead => $composableBuilder(
    column: $table.lastRead,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReadRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReadRecordsTable> {
  $$ReadRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookName => $composableBuilder(
    column: $table.bookName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get readTime => $composableBuilder(
    column: $table.readTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastRead => $composableBuilder(
    column: $table.lastRead,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReadRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReadRecordsTable> {
  $$ReadRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get bookName =>
      $composableBuilder(column: $table.bookName, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get readTime =>
      $composableBuilder(column: $table.readTime, builder: (column) => column);

  GeneratedColumn<int> get lastRead =>
      $composableBuilder(column: $table.lastRead, builder: (column) => column);
}

class $$ReadRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReadRecordsTable,
          ReadRecord,
          $$ReadRecordsTableFilterComposer,
          $$ReadRecordsTableOrderingComposer,
          $$ReadRecordsTableAnnotationComposer,
          $$ReadRecordsTableCreateCompanionBuilder,
          $$ReadRecordsTableUpdateCompanionBuilder,
          (
            ReadRecord,
            BaseReferences<_$AppDatabase, $ReadRecordsTable, ReadRecord>,
          ),
          ReadRecord,
          PrefetchHooks Function()
        > {
  $$ReadRecordsTableTableManager(_$AppDatabase db, $ReadRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$ReadRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$ReadRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () =>
                  $$ReadRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> bookName = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int> readTime = const Value.absent(),
                Value<int> lastRead = const Value.absent(),
              }) => ReadRecordsCompanion(
                id: id,
                bookName: bookName,
                deviceId: deviceId,
                readTime: readTime,
                lastRead: lastRead,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String bookName,
                required String deviceId,
                Value<int> readTime = const Value.absent(),
                Value<int> lastRead = const Value.absent(),
              }) => ReadRecordsCompanion.insert(
                id: id,
                bookName: bookName,
                deviceId: deviceId,
                readTime: readTime,
                lastRead: lastRead,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReadRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReadRecordsTable,
      ReadRecord,
      $$ReadRecordsTableFilterComposer,
      $$ReadRecordsTableOrderingComposer,
      $$ReadRecordsTableAnnotationComposer,
      $$ReadRecordsTableCreateCompanionBuilder,
      $$ReadRecordsTableUpdateCompanionBuilder,
      (
        ReadRecord,
        BaseReferences<_$AppDatabase, $ReadRecordsTable, ReadRecord>,
      ),
      ReadRecord,
      PrefetchHooks Function()
    >;
typedef $$ServersTableCreateCompanionBuilder =
    ServersCompanion Function({
      Value<int> id,
      required String name,
      required String type,
      Value<String?> config,
      Value<int> sortNumber,
    });
typedef $$ServersTableUpdateCompanionBuilder =
    ServersCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> type,
      Value<String?> config,
      Value<int> sortNumber,
    });

class $$ServersTableFilterComposer
    extends Composer<_$AppDatabase, $ServersTable> {
  $$ServersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get config => $composableBuilder(
    column: $table.config,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortNumber => $composableBuilder(
    column: $table.sortNumber,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ServersTableOrderingComposer
    extends Composer<_$AppDatabase, $ServersTable> {
  $$ServersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get config => $composableBuilder(
    column: $table.config,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortNumber => $composableBuilder(
    column: $table.sortNumber,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ServersTableAnnotationComposer
    extends Composer<_$AppDatabase, $ServersTable> {
  $$ServersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get config =>
      $composableBuilder(column: $table.config, builder: (column) => column);

  GeneratedColumn<int> get sortNumber => $composableBuilder(
    column: $table.sortNumber,
    builder: (column) => column,
  );
}

class $$ServersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ServersTable,
          Server,
          $$ServersTableFilterComposer,
          $$ServersTableOrderingComposer,
          $$ServersTableAnnotationComposer,
          $$ServersTableCreateCompanionBuilder,
          $$ServersTableUpdateCompanionBuilder,
          (Server, BaseReferences<_$AppDatabase, $ServersTable, Server>),
          Server,
          PrefetchHooks Function()
        > {
  $$ServersTableTableManager(_$AppDatabase db, $ServersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$ServersTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$ServersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$ServersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> config = const Value.absent(),
                Value<int> sortNumber = const Value.absent(),
              }) => ServersCompanion(
                id: id,
                name: name,
                type: type,
                config: config,
                sortNumber: sortNumber,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String type,
                Value<String?> config = const Value.absent(),
                Value<int> sortNumber = const Value.absent(),
              }) => ServersCompanion.insert(
                id: id,
                name: name,
                type: type,
                config: config,
                sortNumber: sortNumber,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ServersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ServersTable,
      Server,
      $$ServersTableFilterComposer,
      $$ServersTableOrderingComposer,
      $$ServersTableAnnotationComposer,
      $$ServersTableCreateCompanionBuilder,
      $$ServersTableUpdateCompanionBuilder,
      (Server, BaseReferences<_$AppDatabase, $ServersTable, Server>),
      Server,
      PrefetchHooks Function()
    >;
typedef $$TxtTocRulesTableCreateCompanionBuilder =
    TxtTocRulesCompanion Function({
      Value<int> id,
      required String name,
      required String rule,
      Value<String?> example,
      Value<int> serialNumber,
      Value<bool> enable,
    });
typedef $$TxtTocRulesTableUpdateCompanionBuilder =
    TxtTocRulesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> rule,
      Value<String?> example,
      Value<int> serialNumber,
      Value<bool> enable,
    });

class $$TxtTocRulesTableFilterComposer
    extends Composer<_$AppDatabase, $TxtTocRulesTable> {
  $$TxtTocRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rule => $composableBuilder(
    column: $table.rule,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get example => $composableBuilder(
    column: $table.example,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serialNumber => $composableBuilder(
    column: $table.serialNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enable => $composableBuilder(
    column: $table.enable,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TxtTocRulesTableOrderingComposer
    extends Composer<_$AppDatabase, $TxtTocRulesTable> {
  $$TxtTocRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rule => $composableBuilder(
    column: $table.rule,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get example => $composableBuilder(
    column: $table.example,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serialNumber => $composableBuilder(
    column: $table.serialNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enable => $composableBuilder(
    column: $table.enable,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TxtTocRulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TxtTocRulesTable> {
  $$TxtTocRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get rule =>
      $composableBuilder(column: $table.rule, builder: (column) => column);

  GeneratedColumn<String> get example =>
      $composableBuilder(column: $table.example, builder: (column) => column);

  GeneratedColumn<int> get serialNumber => $composableBuilder(
    column: $table.serialNumber,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enable =>
      $composableBuilder(column: $table.enable, builder: (column) => column);
}

class $$TxtTocRulesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TxtTocRulesTable,
          TxtTocRule,
          $$TxtTocRulesTableFilterComposer,
          $$TxtTocRulesTableOrderingComposer,
          $$TxtTocRulesTableAnnotationComposer,
          $$TxtTocRulesTableCreateCompanionBuilder,
          $$TxtTocRulesTableUpdateCompanionBuilder,
          (
            TxtTocRule,
            BaseReferences<_$AppDatabase, $TxtTocRulesTable, TxtTocRule>,
          ),
          TxtTocRule,
          PrefetchHooks Function()
        > {
  $$TxtTocRulesTableTableManager(_$AppDatabase db, $TxtTocRulesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$TxtTocRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$TxtTocRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () =>
                  $$TxtTocRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> rule = const Value.absent(),
                Value<String?> example = const Value.absent(),
                Value<int> serialNumber = const Value.absent(),
                Value<bool> enable = const Value.absent(),
              }) => TxtTocRulesCompanion(
                id: id,
                name: name,
                rule: rule,
                example: example,
                serialNumber: serialNumber,
                enable: enable,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String rule,
                Value<String?> example = const Value.absent(),
                Value<int> serialNumber = const Value.absent(),
                Value<bool> enable = const Value.absent(),
              }) => TxtTocRulesCompanion.insert(
                id: id,
                name: name,
                rule: rule,
                example: example,
                serialNumber: serialNumber,
                enable: enable,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TxtTocRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TxtTocRulesTable,
      TxtTocRule,
      $$TxtTocRulesTableFilterComposer,
      $$TxtTocRulesTableOrderingComposer,
      $$TxtTocRulesTableAnnotationComposer,
      $$TxtTocRulesTableCreateCompanionBuilder,
      $$TxtTocRulesTableUpdateCompanionBuilder,
      (
        TxtTocRule,
        BaseReferences<_$AppDatabase, $TxtTocRulesTable, TxtTocRule>,
      ),
      TxtTocRule,
      PrefetchHooks Function()
    >;
typedef $$CacheTableTableCreateCompanionBuilder =
    CacheTableCompanion Function({
      required String key,
      Value<String?> value,
      Value<int> deadline,
      Value<int> rowid,
    });
typedef $$CacheTableTableUpdateCompanionBuilder =
    CacheTableCompanion Function({
      Value<String> key,
      Value<String?> value,
      Value<int> deadline,
      Value<int> rowid,
    });

class $$CacheTableTableFilterComposer
    extends Composer<_$AppDatabase, $CacheTableTable> {
  $$CacheTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deadline => $composableBuilder(
    column: $table.deadline,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CacheTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CacheTableTable> {
  $$CacheTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deadline => $composableBuilder(
    column: $table.deadline,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CacheTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CacheTableTable> {
  $$CacheTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get deadline =>
      $composableBuilder(column: $table.deadline, builder: (column) => column);
}

class $$CacheTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CacheTableTable,
          Cache,
          $$CacheTableTableFilterComposer,
          $$CacheTableTableOrderingComposer,
          $$CacheTableTableAnnotationComposer,
          $$CacheTableTableCreateCompanionBuilder,
          $$CacheTableTableUpdateCompanionBuilder,
          (Cache, BaseReferences<_$AppDatabase, $CacheTableTable, Cache>),
          Cache,
          PrefetchHooks Function()
        > {
  $$CacheTableTableTableManager(_$AppDatabase db, $CacheTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$CacheTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$CacheTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$CacheTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String?> value = const Value.absent(),
                Value<int> deadline = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CacheTableCompanion(
                key: key,
                value: value,
                deadline: deadline,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                Value<String?> value = const Value.absent(),
                Value<int> deadline = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CacheTableCompanion.insert(
                key: key,
                value: value,
                deadline: deadline,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CacheTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CacheTableTable,
      Cache,
      $$CacheTableTableFilterComposer,
      $$CacheTableTableOrderingComposer,
      $$CacheTableTableAnnotationComposer,
      $$CacheTableTableCreateCompanionBuilder,
      $$CacheTableTableUpdateCompanionBuilder,
      (Cache, BaseReferences<_$AppDatabase, $CacheTableTable, Cache>),
      Cache,
      PrefetchHooks Function()
    >;
typedef $$KeyboardAssistsTableCreateCompanionBuilder =
    KeyboardAssistsCompanion Function({
      required String key,
      Value<int> type,
      Value<String> value,
      Value<int> serialNo,
      Value<int> rowid,
    });
typedef $$KeyboardAssistsTableUpdateCompanionBuilder =
    KeyboardAssistsCompanion Function({
      Value<String> key,
      Value<int> type,
      Value<String> value,
      Value<int> serialNo,
      Value<int> rowid,
    });

class $$KeyboardAssistsTableFilterComposer
    extends Composer<_$AppDatabase, $KeyboardAssistsTable> {
  $$KeyboardAssistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<String, String, String> get value =>
      $composableBuilder(
        column: $table.value,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get serialNo => $composableBuilder(
    column: $table.serialNo,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KeyboardAssistsTableOrderingComposer
    extends Composer<_$AppDatabase, $KeyboardAssistsTable> {
  $$KeyboardAssistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serialNo => $composableBuilder(
    column: $table.serialNo,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KeyboardAssistsTableAnnotationComposer
    extends Composer<_$AppDatabase, $KeyboardAssistsTable> {
  $$KeyboardAssistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumnWithTypeConverter<String, String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get serialNo =>
      $composableBuilder(column: $table.serialNo, builder: (column) => column);
}

class $$KeyboardAssistsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KeyboardAssistsTable,
          KeyboardAssist,
          $$KeyboardAssistsTableFilterComposer,
          $$KeyboardAssistsTableOrderingComposer,
          $$KeyboardAssistsTableAnnotationComposer,
          $$KeyboardAssistsTableCreateCompanionBuilder,
          $$KeyboardAssistsTableUpdateCompanionBuilder,
          (
            KeyboardAssist,
            BaseReferences<
              _$AppDatabase,
              $KeyboardAssistsTable,
              KeyboardAssist
            >,
          ),
          KeyboardAssist,
          PrefetchHooks Function()
        > {
  $$KeyboardAssistsTableTableManager(
    _$AppDatabase db,
    $KeyboardAssistsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () =>
                  $$KeyboardAssistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$KeyboardAssistsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$KeyboardAssistsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<int> type = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> serialNo = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KeyboardAssistsCompanion(
                key: key,
                type: type,
                value: value,
                serialNo: serialNo,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                Value<int> type = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> serialNo = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KeyboardAssistsCompanion.insert(
                key: key,
                type: type,
                value: value,
                serialNo: serialNo,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KeyboardAssistsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KeyboardAssistsTable,
      KeyboardAssist,
      $$KeyboardAssistsTableFilterComposer,
      $$KeyboardAssistsTableOrderingComposer,
      $$KeyboardAssistsTableAnnotationComposer,
      $$KeyboardAssistsTableCreateCompanionBuilder,
      $$KeyboardAssistsTableUpdateCompanionBuilder,
      (
        KeyboardAssist,
        BaseReferences<_$AppDatabase, $KeyboardAssistsTable, KeyboardAssist>,
      ),
      KeyboardAssist,
      PrefetchHooks Function()
    >;
typedef $$RuleSubsTableCreateCompanionBuilder =
    RuleSubsCompanion Function({
      Value<int> id,
      required String name,
      required String url,
      Value<int> type,
      Value<bool> enabled,
      Value<int> order,
    });
typedef $$RuleSubsTableUpdateCompanionBuilder =
    RuleSubsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> url,
      Value<int> type,
      Value<bool> enabled,
      Value<int> order,
    });

class $$RuleSubsTableFilterComposer
    extends Composer<_$AppDatabase, $RuleSubsTable> {
  $$RuleSubsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get order => $composableBuilder(
    column: $table.order,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RuleSubsTableOrderingComposer
    extends Composer<_$AppDatabase, $RuleSubsTable> {
  $$RuleSubsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get order => $composableBuilder(
    column: $table.order,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RuleSubsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RuleSubsTable> {
  $$RuleSubsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get order =>
      $composableBuilder(column: $table.order, builder: (column) => column);
}

class $$RuleSubsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RuleSubsTable,
          RuleSub,
          $$RuleSubsTableFilterComposer,
          $$RuleSubsTableOrderingComposer,
          $$RuleSubsTableAnnotationComposer,
          $$RuleSubsTableCreateCompanionBuilder,
          $$RuleSubsTableUpdateCompanionBuilder,
          (RuleSub, BaseReferences<_$AppDatabase, $RuleSubsTable, RuleSub>),
          RuleSub,
          PrefetchHooks Function()
        > {
  $$RuleSubsTableTableManager(_$AppDatabase db, $RuleSubsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$RuleSubsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$RuleSubsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$RuleSubsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<int> type = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> order = const Value.absent(),
              }) => RuleSubsCompanion(
                id: id,
                name: name,
                url: url,
                type: type,
                enabled: enabled,
                order: order,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String url,
                Value<int> type = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> order = const Value.absent(),
              }) => RuleSubsCompanion.insert(
                id: id,
                name: name,
                url: url,
                type: type,
                enabled: enabled,
                order: order,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RuleSubsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RuleSubsTable,
      RuleSub,
      $$RuleSubsTableFilterComposer,
      $$RuleSubsTableOrderingComposer,
      $$RuleSubsTableAnnotationComposer,
      $$RuleSubsTableCreateCompanionBuilder,
      $$RuleSubsTableUpdateCompanionBuilder,
      (RuleSub, BaseReferences<_$AppDatabase, $RuleSubsTable, RuleSub>),
      RuleSub,
      PrefetchHooks Function()
    >;
typedef $$SourceSubscriptionsTableCreateCompanionBuilder =
    SourceSubscriptionsCompanion Function({
      required String url,
      required String name,
      Value<int> type,
      Value<bool> enabled,
      Value<int> order,
      Value<int> rowid,
    });
typedef $$SourceSubscriptionsTableUpdateCompanionBuilder =
    SourceSubscriptionsCompanion Function({
      Value<String> url,
      Value<String> name,
      Value<int> type,
      Value<bool> enabled,
      Value<int> order,
      Value<int> rowid,
    });

class $$SourceSubscriptionsTableFilterComposer
    extends Composer<_$AppDatabase, $SourceSubscriptionsTable> {
  $$SourceSubscriptionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get order => $composableBuilder(
    column: $table.order,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SourceSubscriptionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SourceSubscriptionsTable> {
  $$SourceSubscriptionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get order => $composableBuilder(
    column: $table.order,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SourceSubscriptionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SourceSubscriptionsTable> {
  $$SourceSubscriptionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get order =>
      $composableBuilder(column: $table.order, builder: (column) => column);
}

class $$SourceSubscriptionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SourceSubscriptionsTable,
          SourceSubscription,
          $$SourceSubscriptionsTableFilterComposer,
          $$SourceSubscriptionsTableOrderingComposer,
          $$SourceSubscriptionsTableAnnotationComposer,
          $$SourceSubscriptionsTableCreateCompanionBuilder,
          $$SourceSubscriptionsTableUpdateCompanionBuilder,
          (
            SourceSubscription,
            BaseReferences<
              _$AppDatabase,
              $SourceSubscriptionsTable,
              SourceSubscription
            >,
          ),
          SourceSubscription,
          PrefetchHooks Function()
        > {
  $$SourceSubscriptionsTableTableManager(
    _$AppDatabase db,
    $SourceSubscriptionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$SourceSubscriptionsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$SourceSubscriptionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$SourceSubscriptionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> url = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> type = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> order = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SourceSubscriptionsCompanion(
                url: url,
                name: name,
                type: type,
                enabled: enabled,
                order: order,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String url,
                required String name,
                Value<int> type = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> order = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SourceSubscriptionsCompanion.insert(
                url: url,
                name: name,
                type: type,
                enabled: enabled,
                order: order,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SourceSubscriptionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SourceSubscriptionsTable,
      SourceSubscription,
      $$SourceSubscriptionsTableFilterComposer,
      $$SourceSubscriptionsTableOrderingComposer,
      $$SourceSubscriptionsTableAnnotationComposer,
      $$SourceSubscriptionsTableCreateCompanionBuilder,
      $$SourceSubscriptionsTableUpdateCompanionBuilder,
      (
        SourceSubscription,
        BaseReferences<
          _$AppDatabase,
          $SourceSubscriptionsTable,
          SourceSubscription
        >,
      ),
      SourceSubscription,
      PrefetchHooks Function()
    >;
typedef $$SearchBooksTableCreateCompanionBuilder =
    SearchBooksCompanion Function({
      required String bookUrl,
      required String name,
      Value<String?> author,
      Value<String?> kind,
      Value<String?> coverUrl,
      Value<String?> intro,
      Value<String?> wordCount,
      Value<String?> latestChapterTitle,
      Value<String> origin,
      Value<String?> originName,
      Value<int> originOrder,
      Value<int> type,
      Value<int> addTime,
      Value<String?> variable,
      Value<String?> tocUrl,
      Value<int> rowid,
    });
typedef $$SearchBooksTableUpdateCompanionBuilder =
    SearchBooksCompanion Function({
      Value<String> bookUrl,
      Value<String> name,
      Value<String?> author,
      Value<String?> kind,
      Value<String?> coverUrl,
      Value<String?> intro,
      Value<String?> wordCount,
      Value<String?> latestChapterTitle,
      Value<String> origin,
      Value<String?> originName,
      Value<int> originOrder,
      Value<int> type,
      Value<int> addTime,
      Value<String?> variable,
      Value<String?> tocUrl,
      Value<int> rowid,
    });

class $$SearchBooksTableFilterComposer
    extends Composer<_$AppDatabase, $SearchBooksTable> {
  $$SearchBooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get intro => $composableBuilder(
    column: $table.intro,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wordCount => $composableBuilder(
    column: $table.wordCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get latestChapterTitle => $composableBuilder(
    column: $table.latestChapterTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<String, String, String> get origin =>
      $composableBuilder(
        column: $table.origin,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get originName => $composableBuilder(
    column: $table.originName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get originOrder => $composableBuilder(
    column: $table.originOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addTime => $composableBuilder(
    column: $table.addTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get variable => $composableBuilder(
    column: $table.variable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tocUrl => $composableBuilder(
    column: $table.tocUrl,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SearchBooksTableOrderingComposer
    extends Composer<_$AppDatabase, $SearchBooksTable> {
  $$SearchBooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get intro => $composableBuilder(
    column: $table.intro,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wordCount => $composableBuilder(
    column: $table.wordCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get latestChapterTitle => $composableBuilder(
    column: $table.latestChapterTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originName => $composableBuilder(
    column: $table.originName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get originOrder => $composableBuilder(
    column: $table.originOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addTime => $composableBuilder(
    column: $table.addTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get variable => $composableBuilder(
    column: $table.variable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tocUrl => $composableBuilder(
    column: $table.tocUrl,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SearchBooksTableAnnotationComposer
    extends Composer<_$AppDatabase, $SearchBooksTable> {
  $$SearchBooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookUrl =>
      $composableBuilder(column: $table.bookUrl, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get coverUrl =>
      $composableBuilder(column: $table.coverUrl, builder: (column) => column);

  GeneratedColumn<String> get intro =>
      $composableBuilder(column: $table.intro, builder: (column) => column);

  GeneratedColumn<String> get wordCount =>
      $composableBuilder(column: $table.wordCount, builder: (column) => column);

  GeneratedColumn<String> get latestChapterTitle => $composableBuilder(
    column: $table.latestChapterTitle,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<String, String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get originName => $composableBuilder(
    column: $table.originName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get originOrder => $composableBuilder(
    column: $table.originOrder,
    builder: (column) => column,
  );

  GeneratedColumn<int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get addTime =>
      $composableBuilder(column: $table.addTime, builder: (column) => column);

  GeneratedColumn<String> get variable =>
      $composableBuilder(column: $table.variable, builder: (column) => column);

  GeneratedColumn<String> get tocUrl =>
      $composableBuilder(column: $table.tocUrl, builder: (column) => column);
}

class $$SearchBooksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SearchBooksTable,
          SearchBook,
          $$SearchBooksTableFilterComposer,
          $$SearchBooksTableOrderingComposer,
          $$SearchBooksTableAnnotationComposer,
          $$SearchBooksTableCreateCompanionBuilder,
          $$SearchBooksTableUpdateCompanionBuilder,
          (
            SearchBook,
            BaseReferences<_$AppDatabase, $SearchBooksTable, SearchBook>,
          ),
          SearchBook,
          PrefetchHooks Function()
        > {
  $$SearchBooksTableTableManager(_$AppDatabase db, $SearchBooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$SearchBooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$SearchBooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () =>
                  $$SearchBooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookUrl = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> author = const Value.absent(),
                Value<String?> kind = const Value.absent(),
                Value<String?> coverUrl = const Value.absent(),
                Value<String?> intro = const Value.absent(),
                Value<String?> wordCount = const Value.absent(),
                Value<String?> latestChapterTitle = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String?> originName = const Value.absent(),
                Value<int> originOrder = const Value.absent(),
                Value<int> type = const Value.absent(),
                Value<int> addTime = const Value.absent(),
                Value<String?> variable = const Value.absent(),
                Value<String?> tocUrl = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SearchBooksCompanion(
                bookUrl: bookUrl,
                name: name,
                author: author,
                kind: kind,
                coverUrl: coverUrl,
                intro: intro,
                wordCount: wordCount,
                latestChapterTitle: latestChapterTitle,
                origin: origin,
                originName: originName,
                originOrder: originOrder,
                type: type,
                addTime: addTime,
                variable: variable,
                tocUrl: tocUrl,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookUrl,
                required String name,
                Value<String?> author = const Value.absent(),
                Value<String?> kind = const Value.absent(),
                Value<String?> coverUrl = const Value.absent(),
                Value<String?> intro = const Value.absent(),
                Value<String?> wordCount = const Value.absent(),
                Value<String?> latestChapterTitle = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String?> originName = const Value.absent(),
                Value<int> originOrder = const Value.absent(),
                Value<int> type = const Value.absent(),
                Value<int> addTime = const Value.absent(),
                Value<String?> variable = const Value.absent(),
                Value<String?> tocUrl = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SearchBooksCompanion.insert(
                bookUrl: bookUrl,
                name: name,
                author: author,
                kind: kind,
                coverUrl: coverUrl,
                intro: intro,
                wordCount: wordCount,
                latestChapterTitle: latestChapterTitle,
                origin: origin,
                originName: originName,
                originOrder: originOrder,
                type: type,
                addTime: addTime,
                variable: variable,
                tocUrl: tocUrl,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SearchBooksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SearchBooksTable,
      SearchBook,
      $$SearchBooksTableFilterComposer,
      $$SearchBooksTableOrderingComposer,
      $$SearchBooksTableAnnotationComposer,
      $$SearchBooksTableCreateCompanionBuilder,
      $$SearchBooksTableUpdateCompanionBuilder,
      (
        SearchBook,
        BaseReferences<_$AppDatabase, $SearchBooksTable, SearchBook>,
      ),
      SearchBook,
      PrefetchHooks Function()
    >;
typedef $$DownloadTasksTableCreateCompanionBuilder =
    DownloadTasksCompanion Function({
      required String bookUrl,
      required String bookName,
      Value<int> startChapterIndex,
      Value<int> endChapterIndex,
      Value<int> currentChapterIndex,
      Value<int> totalCount,
      Value<int> status,
      Value<int> successCount,
      Value<int> errorCount,
      Value<int> lastUpdateTime,
      Value<int> rowid,
    });
typedef $$DownloadTasksTableUpdateCompanionBuilder =
    DownloadTasksCompanion Function({
      Value<String> bookUrl,
      Value<String> bookName,
      Value<int> startChapterIndex,
      Value<int> endChapterIndex,
      Value<int> currentChapterIndex,
      Value<int> totalCount,
      Value<int> status,
      Value<int> successCount,
      Value<int> errorCount,
      Value<int> lastUpdateTime,
      Value<int> rowid,
    });

class $$DownloadTasksTableFilterComposer
    extends Composer<_$AppDatabase, $DownloadTasksTable> {
  $$DownloadTasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookName => $composableBuilder(
    column: $table.bookName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startChapterIndex => $composableBuilder(
    column: $table.startChapterIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endChapterIndex => $composableBuilder(
    column: $table.endChapterIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentChapterIndex => $composableBuilder(
    column: $table.currentChapterIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalCount => $composableBuilder(
    column: $table.totalCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get successCount => $composableBuilder(
    column: $table.successCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get errorCount => $composableBuilder(
    column: $table.errorCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastUpdateTime => $composableBuilder(
    column: $table.lastUpdateTime,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DownloadTasksTableOrderingComposer
    extends Composer<_$AppDatabase, $DownloadTasksTable> {
  $$DownloadTasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookName => $composableBuilder(
    column: $table.bookName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startChapterIndex => $composableBuilder(
    column: $table.startChapterIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endChapterIndex => $composableBuilder(
    column: $table.endChapterIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentChapterIndex => $composableBuilder(
    column: $table.currentChapterIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalCount => $composableBuilder(
    column: $table.totalCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get successCount => $composableBuilder(
    column: $table.successCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get errorCount => $composableBuilder(
    column: $table.errorCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastUpdateTime => $composableBuilder(
    column: $table.lastUpdateTime,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DownloadTasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $DownloadTasksTable> {
  $$DownloadTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookUrl =>
      $composableBuilder(column: $table.bookUrl, builder: (column) => column);

  GeneratedColumn<String> get bookName =>
      $composableBuilder(column: $table.bookName, builder: (column) => column);

  GeneratedColumn<int> get startChapterIndex => $composableBuilder(
    column: $table.startChapterIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endChapterIndex => $composableBuilder(
    column: $table.endChapterIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get currentChapterIndex => $composableBuilder(
    column: $table.currentChapterIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalCount => $composableBuilder(
    column: $table.totalCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get successCount => $composableBuilder(
    column: $table.successCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get errorCount => $composableBuilder(
    column: $table.errorCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastUpdateTime => $composableBuilder(
    column: $table.lastUpdateTime,
    builder: (column) => column,
  );
}

class $$DownloadTasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DownloadTasksTable,
          DownloadTask,
          $$DownloadTasksTableFilterComposer,
          $$DownloadTasksTableOrderingComposer,
          $$DownloadTasksTableAnnotationComposer,
          $$DownloadTasksTableCreateCompanionBuilder,
          $$DownloadTasksTableUpdateCompanionBuilder,
          (
            DownloadTask,
            BaseReferences<_$AppDatabase, $DownloadTasksTable, DownloadTask>,
          ),
          DownloadTask,
          PrefetchHooks Function()
        > {
  $$DownloadTasksTableTableManager(_$AppDatabase db, $DownloadTasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$DownloadTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () =>
                  $$DownloadTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$DownloadTasksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> bookUrl = const Value.absent(),
                Value<String> bookName = const Value.absent(),
                Value<int> startChapterIndex = const Value.absent(),
                Value<int> endChapterIndex = const Value.absent(),
                Value<int> currentChapterIndex = const Value.absent(),
                Value<int> totalCount = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<int> successCount = const Value.absent(),
                Value<int> errorCount = const Value.absent(),
                Value<int> lastUpdateTime = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadTasksCompanion(
                bookUrl: bookUrl,
                bookName: bookName,
                startChapterIndex: startChapterIndex,
                endChapterIndex: endChapterIndex,
                currentChapterIndex: currentChapterIndex,
                totalCount: totalCount,
                status: status,
                successCount: successCount,
                errorCount: errorCount,
                lastUpdateTime: lastUpdateTime,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookUrl,
                required String bookName,
                Value<int> startChapterIndex = const Value.absent(),
                Value<int> endChapterIndex = const Value.absent(),
                Value<int> currentChapterIndex = const Value.absent(),
                Value<int> totalCount = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<int> successCount = const Value.absent(),
                Value<int> errorCount = const Value.absent(),
                Value<int> lastUpdateTime = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadTasksCompanion.insert(
                bookUrl: bookUrl,
                bookName: bookName,
                startChapterIndex: startChapterIndex,
                endChapterIndex: endChapterIndex,
                currentChapterIndex: currentChapterIndex,
                totalCount: totalCount,
                status: status,
                successCount: successCount,
                errorCount: errorCount,
                lastUpdateTime: lastUpdateTime,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DownloadTasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DownloadTasksTable,
      DownloadTask,
      $$DownloadTasksTableFilterComposer,
      $$DownloadTasksTableOrderingComposer,
      $$DownloadTasksTableAnnotationComposer,
      $$DownloadTasksTableCreateCompanionBuilder,
      $$DownloadTasksTableUpdateCompanionBuilder,
      (
        DownloadTask,
        BaseReferences<_$AppDatabase, $DownloadTasksTable, DownloadTask>,
      ),
      DownloadTask,
      PrefetchHooks Function()
    >;
typedef $$SearchKeywordsTableCreateCompanionBuilder =
    SearchKeywordsCompanion Function({
      required String word,
      Value<int> usage,
      Value<int> lastUseTime,
      Value<int> rowid,
    });
typedef $$SearchKeywordsTableUpdateCompanionBuilder =
    SearchKeywordsCompanion Function({
      Value<String> word,
      Value<int> usage,
      Value<int> lastUseTime,
      Value<int> rowid,
    });

class $$SearchKeywordsTableFilterComposer
    extends Composer<_$AppDatabase, $SearchKeywordsTable> {
  $$SearchKeywordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get word => $composableBuilder(
    column: $table.word,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get usage => $composableBuilder(
    column: $table.usage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastUseTime => $composableBuilder(
    column: $table.lastUseTime,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SearchKeywordsTableOrderingComposer
    extends Composer<_$AppDatabase, $SearchKeywordsTable> {
  $$SearchKeywordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get word => $composableBuilder(
    column: $table.word,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get usage => $composableBuilder(
    column: $table.usage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastUseTime => $composableBuilder(
    column: $table.lastUseTime,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SearchKeywordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SearchKeywordsTable> {
  $$SearchKeywordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get word =>
      $composableBuilder(column: $table.word, builder: (column) => column);

  GeneratedColumn<int> get usage =>
      $composableBuilder(column: $table.usage, builder: (column) => column);

  GeneratedColumn<int> get lastUseTime => $composableBuilder(
    column: $table.lastUseTime,
    builder: (column) => column,
  );
}

class $$SearchKeywordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SearchKeywordsTable,
          SearchKeyword,
          $$SearchKeywordsTableFilterComposer,
          $$SearchKeywordsTableOrderingComposer,
          $$SearchKeywordsTableAnnotationComposer,
          $$SearchKeywordsTableCreateCompanionBuilder,
          $$SearchKeywordsTableUpdateCompanionBuilder,
          (
            SearchKeyword,
            BaseReferences<_$AppDatabase, $SearchKeywordsTable, SearchKeyword>,
          ),
          SearchKeyword,
          PrefetchHooks Function()
        > {
  $$SearchKeywordsTableTableManager(
    _$AppDatabase db,
    $SearchKeywordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$SearchKeywordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () =>
                  $$SearchKeywordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$SearchKeywordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> word = const Value.absent(),
                Value<int> usage = const Value.absent(),
                Value<int> lastUseTime = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SearchKeywordsCompanion(
                word: word,
                usage: usage,
                lastUseTime: lastUseTime,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String word,
                Value<int> usage = const Value.absent(),
                Value<int> lastUseTime = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SearchKeywordsCompanion.insert(
                word: word,
                usage: usage,
                lastUseTime: lastUseTime,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SearchKeywordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SearchKeywordsTable,
      SearchKeyword,
      $$SearchKeywordsTableFilterComposer,
      $$SearchKeywordsTableOrderingComposer,
      $$SearchKeywordsTableAnnotationComposer,
      $$SearchKeywordsTableCreateCompanionBuilder,
      $$SearchKeywordsTableUpdateCompanionBuilder,
      (
        SearchKeyword,
        BaseReferences<_$AppDatabase, $SearchKeywordsTable, SearchKeyword>,
      ),
      SearchKeyword,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db, _db.books);
  $$ChaptersTableTableManager get chapters =>
      $$ChaptersTableTableManager(_db, _db.chapters);
  $$ReaderChapterContentsTableTableManager get readerChapterContents =>
      $$ReaderChapterContentsTableTableManager(_db, _db.readerChapterContents);
  $$BookSourcesTableTableManager get bookSources =>
      $$BookSourcesTableTableManager(_db, _db.bookSources);
  $$BookGroupsTableTableManager get bookGroups =>
      $$BookGroupsTableTableManager(_db, _db.bookGroups);
  $$SearchHistoryTableTableTableManager get searchHistoryTable =>
      $$SearchHistoryTableTableTableManager(_db, _db.searchHistoryTable);
  $$ReplaceRulesTableTableManager get replaceRules =>
      $$ReplaceRulesTableTableManager(_db, _db.replaceRules);
  $$BookmarksTableTableManager get bookmarks =>
      $$BookmarksTableTableManager(_db, _db.bookmarks);
  $$CookiesTableTableManager get cookies =>
      $$CookiesTableTableManager(_db, _db.cookies);
  $$DictRulesTableTableManager get dictRules =>
      $$DictRulesTableTableManager(_db, _db.dictRules);
  $$HttpTtsTableTableTableManager get httpTtsTable =>
      $$HttpTtsTableTableTableManager(_db, _db.httpTtsTable);
  $$ReadRecordsTableTableManager get readRecords =>
      $$ReadRecordsTableTableManager(_db, _db.readRecords);
  $$ServersTableTableManager get servers =>
      $$ServersTableTableManager(_db, _db.servers);
  $$TxtTocRulesTableTableManager get txtTocRules =>
      $$TxtTocRulesTableTableManager(_db, _db.txtTocRules);
  $$CacheTableTableTableManager get cacheTable =>
      $$CacheTableTableTableManager(_db, _db.cacheTable);
  $$KeyboardAssistsTableTableManager get keyboardAssists =>
      $$KeyboardAssistsTableTableManager(_db, _db.keyboardAssists);
  $$RuleSubsTableTableManager get ruleSubs =>
      $$RuleSubsTableTableManager(_db, _db.ruleSubs);
  $$SourceSubscriptionsTableTableManager get sourceSubscriptions =>
      $$SourceSubscriptionsTableTableManager(_db, _db.sourceSubscriptions);
  $$SearchBooksTableTableManager get searchBooks =>
      $$SearchBooksTableTableManager(_db, _db.searchBooks);
  $$DownloadTasksTableTableManager get downloadTasks =>
      $$DownloadTasksTableTableManager(_db, _db.downloadTasks);
  $$SearchKeywordsTableTableManager get searchKeywords =>
      $$SearchKeywordsTableTableManager(_db, _db.searchKeywords);
}
