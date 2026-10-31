/// schema 8 以前的 chapters 表：主鍵只有章節網址。從第一版到 schema 7
/// 欄位都沒變；升級到 schema 8 會重建它，所以從更舊的版本升級的測試也要
/// 先建這張表。
const String legacyChaptersTable = '''
  CREATE TABLE chapters (
    url TEXT NOT NULL,
    title TEXT NOT NULL,
    isVolume INTEGER NOT NULL DEFAULT 0 CHECK (isVolume IN (0, 1)),
    baseUrl TEXT,
    bookUrl TEXT NOT NULL,
    "index" INTEGER NOT NULL,
    isVip INTEGER NOT NULL DEFAULT 0 CHECK (isVip IN (0, 1)),
    isPay INTEGER NOT NULL DEFAULT 0 CHECK (isPay IN (0, 1)),
    resourceUrl TEXT,
    tag TEXT,
    wordCount TEXT,
    start INTEGER,
    "end" INTEGER,
    startFragmentId TEXT,
    endFragmentId TEXT,
    variable TEXT,
    PRIMARY KEY (url)
  )''';
