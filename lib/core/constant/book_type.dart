class BookType {
  /// 8 文本
  static const int text = 0x08;

  /// 16 更新失敗
  static const int updateError = 0x10;

  /// 32 有聲（Legado 備份裡的書用這個位元；夜讀的書記的是書源類型）
  static const int audio = 0x20;

  /// 64 圖片
  static const int image = 0x40;

  /// 128 只提供下載服務的網站
  static const int webFile = 0x80;

  /// 256 本地
  static const int local = 0x100;

  /// 512 壓縮包 表明書籍文件是從壓縮包內解壓來的
  static const int archive = 0x200;

  /// 1024 未正式加入到書架的臨時閱讀書籍
  static const int notShelf = 0x400;

  /// 所有可以從書源轉換的書籍類型
  static const int allBookType = text | image | webFile;

  static const int allBookTypeLocal = text | image | webFile | local;

  /// 夜讀匯入的本地書的書源標誌。
  static const String localOrigin = 'local';

  /// Legado 的本地書書源標誌，從 Legado 備份還原的書用它。
  static const String localTag = 'loc_book';

  static bool isImage(int type) => (type & image) != 0;
  static bool isLocal(int type) => (type & local) != 0;
  static bool isOnShelf(int type) => (type & notShelf) == 0;
}
