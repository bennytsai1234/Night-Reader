/// schema 9 以前的 books 表：還沒有 progressTime。升級到 schema 9 會在這張表
/// 加欄位，所以從更舊的版本升級的測試也要先建這張表。
const String legacyBooksTable = '''
  CREATE TABLE "books" (
    "bookUrl" TEXT NOT NULL, "tocUrl" TEXT NULL, "origin" TEXT NULL,
    "originName" TEXT NULL, "name" TEXT NOT NULL, "author" TEXT NULL,
    "kind" TEXT NULL, "customTag" TEXT NULL, "coverUrl" TEXT NULL,
    "coverLocalPath" TEXT NULL, "customCoverUrl" TEXT NULL,
    "customCoverLocalPath" TEXT NULL, "intro" TEXT NULL,
    "customIntro" TEXT NULL, "charset" TEXT NULL,
    "type" INTEGER NOT NULL DEFAULT 0, "group" INTEGER NOT NULL DEFAULT 0,
    "latestChapterTitle" TEXT NULL,
    "latestChapterTime" INTEGER NOT NULL DEFAULT 0,
    "lastCheckTime" INTEGER NOT NULL DEFAULT 0,
    "lastCheckCount" INTEGER NOT NULL DEFAULT 0,
    "totalChapterNum" INTEGER NOT NULL DEFAULT 0,
    "durChapterTitle" TEXT NULL,
    "chapterIndex" INTEGER NOT NULL DEFAULT 0,
    "charOffset" INTEGER NOT NULL DEFAULT 0,
    "visualOffsetPx" REAL NOT NULL DEFAULT 0.0,
    "readerAnchorJson" TEXT NULL,
    "durChapterTime" INTEGER NOT NULL DEFAULT 0,
    "wordCount" TEXT NULL,
    "canUpdate" INTEGER NOT NULL DEFAULT 1 CHECK ("canUpdate" IN (0, 1)),
    "order" INTEGER NOT NULL DEFAULT 0,
    "originOrder" INTEGER NOT NULL DEFAULT 0,
    "variable" TEXT NULL, "readConfig" TEXT NULL,
    "syncTime" INTEGER NOT NULL DEFAULT 0,
    "isInBookshelf" INTEGER NOT NULL DEFAULT 0 CHECK ("isInBookshelf" IN (0, 1)),
    PRIMARY KEY ("bookUrl")
  )''';
