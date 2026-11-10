class SourceType {
  static const int book = 0;
  static const int audio = 1;
  static const int image = 2;
  static const int file = 3;

  /// 影視書源。Legado 沒有這個值（讀到時當文字書源），源倉庫的影視書源與
  /// 改版 App 用它；夜讀匯入時把類型寫 0、帶影視字樣的也記成它（ADR 0056）。
  static const int video = 4;
}
