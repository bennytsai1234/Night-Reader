const double kReaderContentTopSafeAreaFactor = 0.75;
const double kReaderContentTopSpacing = 4.5;

/// 頁首頁尾資訊的預設字級。
const double kReaderInfoFontSize = 11.0;

/// 頁首資訊列在預設字級時的單行高度。
const double kReaderInfoRowHeight = 24.0;

/// 頁尾資訊列在預設字級時的高度：剛好容納一行資訊文字，上下不另留空白。
/// 正文與頁尾之間的距離由使用者的下邊距決定。
const double kReaderFooterRowHeight = 16.0;

/// 頁首頁尾的字每大 1，那一列跟著高這麼多（資訊文字的行高倍率），
/// 字放大後不會被螢幕底邊切掉。
const double _kReaderInfoRowGrowth = 1.3;

/// 頁首資訊列在字級 [fontSize] 時的高度。
double readerInfoRowHeightFor(double fontSize) =>
    kReaderInfoRowHeight +
    (fontSize - kReaderInfoFontSize) * _kReaderInfoRowGrowth;

/// 頁尾資訊列在字級 [fontSize] 時的高度。
double readerFooterRowHeightFor(double fontSize) =>
    kReaderFooterRowHeight +
    (fontSize - kReaderInfoFontSize) * _kReaderInfoRowGrowth;
