/// schema 6 到 13 的 download_tasks 表：還沒有失敗類型、訊息與章節。升級到
/// schema 14 會在這張表加欄位，所以從這幾版升級的測試也要先建這張表。
const String legacyDownloadTasksTable = '''
  CREATE TABLE download_tasks (
    bookUrl TEXT NOT NULL PRIMARY KEY,
    bookName TEXT NOT NULL,
    startChapterUrl TEXT NULL,
    endChapterUrl TEXT NULL,
    currentChapterIndex INTEGER NOT NULL DEFAULT 0,
    totalChapterCount INTEGER NOT NULL DEFAULT 0,
    status INTEGER NOT NULL DEFAULT 0,
    successCount INTEGER NOT NULL DEFAULT 0,
    errorCount INTEGER NOT NULL DEFAULT 0,
    addTime INTEGER NOT NULL DEFAULT 0,
    sortOrder INTEGER NOT NULL DEFAULT 0
  )''';

/// 把現在的資料庫退回 schema 13 以前時，download_tasks 要刪掉的欄位。
const List<String> dropDownloadFailureColumns = [
  'ALTER TABLE download_tasks DROP COLUMN lastErrorReason',
  'ALTER TABLE download_tasks DROP COLUMN lastErrorMessage',
  'ALTER TABLE download_tasks DROP COLUMN lastErrorChapterIndex',
];
