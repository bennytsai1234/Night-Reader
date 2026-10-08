import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_tap_action.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_highlight_style.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_info_item.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReaderV2PrefsSnapshot {
  final double fontSize;

  /// 章節標題字號。未保存過時沿用舊版規則（正文 + 4），外觀不變。
  final double titleFontSize;
  final double lineHeight;
  final double paragraphSpacing;

  /// 章末與下一章標題之間的空白（行）。
  final double chapterSpacing;
  final double letterSpacing;
  final int textIndent;
  final double autoPageSpeed;
  final int chineseConvert;
  final bool showAddToShelfAlert;
  final List<int> clickActions;

  /// 正文左右邊距（px）。
  final double paddingHorizontal;

  /// 正文與頁首之間的距離（px）；隱藏狀態列時從鏡頭挖孔下緣算起。
  final double paddingTop;

  /// 正文與頁尾資訊列之間的距離（px）；沒有頁尾時與畫面底部之間。
  final double paddingBottom;

  /// 頁尾資訊列底部到畫面底部的距離（px）；null 表示跟隨系統底部內距。
  final double? footerOffset;

  /// 閱讀時隱藏系統狀態列（時間、訊號、電量）。
  final bool hideStatusBar;
  final ReaderV2InfoSlots headerInfo;
  final ReaderV2InfoSlots footerInfo;

  /// 朗讀高亮與選字反白的顏色，以及朗讀高亮的深淺。
  final ReaderV2HighlightColor highlightColor;
  final double highlightStrength;

  const ReaderV2PrefsSnapshot({
    required this.fontSize,
    required this.titleFontSize,
    required this.lineHeight,
    required this.paragraphSpacing,
    required this.chapterSpacing,
    required this.letterSpacing,
    required this.textIndent,
    required this.autoPageSpeed,
    required this.chineseConvert,
    required this.showAddToShelfAlert,
    required this.clickActions,
    required this.paddingHorizontal,
    required this.paddingTop,
    required this.paddingBottom,
    this.footerOffset,
    required this.hideStatusBar,
    required this.headerInfo,
    required this.footerInfo,
    required this.highlightColor,
    required this.highlightStrength,
  });

  factory ReaderV2PrefsSnapshot.defaults() {
    return ReaderV2PrefsSnapshot(
      fontSize: 18.0,
      titleFontSize: 18.0 + kReaderV2DefaultTitleSizeDelta,
      lineHeight: 1.5,
      paragraphSpacing: 1.0,
      chapterSpacing: 1.0,
      letterSpacing: 0.0,
      textIndent: 2,
      autoPageSpeed: 0.16,
      chineseConvert: 0,
      showAddToShelfAlert: true,
      clickActions: ReaderV2TapAction.defaultGrid(),
      paddingHorizontal: 16.0,
      paddingTop: 0.0,
      // 等同舊版頁尾上方固定的 12px 加上資訊列文字上方的空白。
      paddingBottom: 16.0,
      hideStatusBar: false,
      // 頁首預設關閉：狀態列顯示時多一條頁首只會重複系統時鐘；
      // 隱藏狀態列後由使用者決定鏡頭那一行放什麼。
      headerInfo: const ReaderV2InfoSlots(
        left: ReaderV2InfoItem.none,
        right: ReaderV2InfoItem.none,
      ),
      footerInfo: const ReaderV2InfoSlots(
        left: ReaderV2InfoItem.chapterTitle,
        right: ReaderV2InfoItem.bookProgress,
      ),
      highlightColor: ReaderV2HighlightColor.theme,
      highlightStrength: ReaderV2HighlightStrength.defaultValue,
    );
  }

  ReaderV2PrefsSnapshot copyWith({
    double? fontSize,
    double? titleFontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? chapterSpacing,
    double? letterSpacing,
    int? textIndent,
    double? autoPageSpeed,
    int? chineseConvert,
    bool? showAddToShelfAlert,
    List<int>? clickActions,
    double? paddingHorizontal,
    double? paddingTop,
    double? paddingBottom,
    double? Function()? footerOffset,
    bool? hideStatusBar,
    ReaderV2InfoSlots? headerInfo,
    ReaderV2InfoSlots? footerInfo,
    ReaderV2HighlightColor? highlightColor,
    double? highlightStrength,
  }) {
    return ReaderV2PrefsSnapshot(
      fontSize: fontSize ?? this.fontSize,
      titleFontSize: titleFontSize ?? this.titleFontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      chapterSpacing: chapterSpacing ?? this.chapterSpacing,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      textIndent: textIndent ?? this.textIndent,
      autoPageSpeed: autoPageSpeed ?? this.autoPageSpeed,
      chineseConvert: chineseConvert ?? this.chineseConvert,
      showAddToShelfAlert: showAddToShelfAlert ?? this.showAddToShelfAlert,
      clickActions: clickActions ?? List<int>.from(this.clickActions),
      paddingHorizontal: paddingHorizontal ?? this.paddingHorizontal,
      paddingTop: paddingTop ?? this.paddingTop,
      paddingBottom: paddingBottom ?? this.paddingBottom,
      footerOffset: footerOffset == null ? this.footerOffset : footerOffset(),
      hideStatusBar: hideStatusBar ?? this.hideStatusBar,
      headerInfo: headerInfo ?? this.headerInfo,
      footerInfo: footerInfo ?? this.footerInfo,
      highlightColor: highlightColor ?? this.highlightColor,
      highlightStrength: highlightStrength ?? this.highlightStrength,
    );
  }
}

class ReaderV2PrefsRepository {
  const ReaderV2PrefsRepository();

  /// 自動翻頁速度（每秒滾動畫面高的比例）的合法範圍；
  /// 所有讀寫端（設定 sheet、全域設定頁、AutoPageController）共用此常數。
  static const double minAutoPageSpeed = 0.02;
  static const double maxAutoPageSpeed = 0.45;

  /// 版面邊距的合法範圍（px）。
  static const double minPagePadding = 0.0;
  static const double maxPagePadding = 64.0;

  /// 章節間距的合法範圍（行）。
  static const double minChapterSpacing = 0.0;
  static const double maxChapterSpacing = 5.0;

  static ReaderV2PrefsSnapshot? _latestSnapshot;

  static ReaderV2PrefsSnapshot get cachedSnapshot =>
      _latestSnapshot ?? ReaderV2PrefsSnapshot.defaults();

  Future<ReaderV2PrefsSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final defaults = ReaderV2PrefsSnapshot.defaults();
    final fontSize =
        prefs.getDouble(PreferKey.readerFontSize) ?? defaults.fontSize;
    final snapshot = ReaderV2PrefsSnapshot(
      fontSize: fontSize,
      titleFontSize:
          prefs.getDouble(PreferKey.readerTitleFontSize) ??
          fontSize + kReaderV2DefaultTitleSizeDelta,
      lineHeight:
          prefs.getDouble(PreferKey.readerLineHeight) ?? defaults.lineHeight,
      paragraphSpacing:
          prefs.getDouble(PreferKey.readerParagraphSpacing) ??
          defaults.paragraphSpacing,
      chapterSpacing: _normalizeChapterSpacing(
        prefs.getDouble(PreferKey.readerChapterSpacing),
        defaults.chapterSpacing,
      ),
      letterSpacing:
          prefs.getDouble(PreferKey.readerLetterSpacing) ??
          defaults.letterSpacing,
      textIndent:
          prefs.getInt(PreferKey.readerTextIndent) ?? defaults.textIndent,
      autoPageSpeed: _normalizeAutoPageSpeed(
        prefs.getDouble(PreferKey.readerAutoPageSpeed) ??
            prefs.getInt(PreferKey.autoReadSpeed)?.toDouble(),
      ),
      chineseConvert:
          prefs.getInt(PreferKey.readerChineseConvert) ??
          defaults.chineseConvert,
      showAddToShelfAlert:
          prefs.getBool(PreferKey.showAddToShelfAlert) ??
          defaults.showAddToShelfAlert,
      clickActions: _parseClickActions(
        prefs.getString(PreferKey.readerClickActions),
      ),
      paddingHorizontal: _normalizePagePadding(
        prefs.getDouble(PreferKey.readerPaddingHorizontal),
        defaults.paddingHorizontal,
      ),
      paddingTop: _normalizePagePadding(
        prefs.getDouble(PreferKey.readerPaddingTop),
        defaults.paddingTop,
      ),
      paddingBottom: _normalizePagePadding(
        prefs.getDouble(PreferKey.readerPaddingBottom),
        defaults.paddingBottom,
      ),
      footerOffset: _normalizeOptionalPagePadding(
        prefs.getDouble(PreferKey.readerFooterOffset),
      ),
      hideStatusBar:
          prefs.getBool(PreferKey.readerHideStatusBar) ?? defaults.hideStatusBar,
      headerInfo:
          ReaderV2InfoSlots.decode(prefs.getString(PreferKey.readerHeaderInfo)) ??
          defaults.headerInfo,
      footerInfo:
          ReaderV2InfoSlots.decode(prefs.getString(PreferKey.readerFooterInfo)) ??
          defaults.footerInfo,
      highlightColor: ReaderV2HighlightColor.parse(
        prefs.getString(PreferKey.readerHighlightColor),
      ),
      highlightStrength: ReaderV2HighlightStrength.normalize(
        prefs.getDouble(PreferKey.readerHighlightStrength),
      ),
    );
    _latestSnapshot = snapshot;
    return snapshot;
  }

  Future<void> saveFontSize(double value) {
    return _setDouble(PreferKey.readerFontSize, value);
  }

  Future<void> saveTitleFontSize(double value) {
    return _setDouble(PreferKey.readerTitleFontSize, value);
  }

  Future<void> saveLineHeight(double value) {
    return _setDouble(PreferKey.readerLineHeight, value);
  }

  Future<void> saveParagraphSpacing(double value) {
    return _setDouble(PreferKey.readerParagraphSpacing, value);
  }

  Future<void> saveChapterSpacing(double value) {
    return _setDouble(PreferKey.readerChapterSpacing, value);
  }

  Future<void> saveLetterSpacing(double value) {
    return _setDouble(PreferKey.readerLetterSpacing, value);
  }

  Future<void> saveTextIndent(int value) {
    return _setInt(PreferKey.readerTextIndent, value);
  }

  Future<void> saveAutoPageSpeed(double value) {
    return _setDouble(
      PreferKey.readerAutoPageSpeed,
      _normalizeAutoPageSpeed(value),
    );
  }

  Future<void> saveChineseConvert(int value) {
    return _setInt(PreferKey.readerChineseConvert, value);
  }

  Future<void> saveShowAddToShelfAlert(bool value) {
    return _setBool(PreferKey.showAddToShelfAlert, value);
  }

  Future<void> saveClickActions(List<int> actions) {
    final normalized = _normalizeClickActions(actions);
    return _setString(PreferKey.readerClickActions, normalized.join(','));
  }

  Future<void> savePaddingHorizontal(double value) {
    return _setDouble(PreferKey.readerPaddingHorizontal, value);
  }

  Future<void> savePaddingTop(double value) {
    return _setDouble(PreferKey.readerPaddingTop, value);
  }

  Future<void> savePaddingBottom(double value) {
    return _setDouble(PreferKey.readerPaddingBottom, value);
  }

  /// null 表示恢復跟隨系統底部內距。
  Future<void> saveFooterOffset(double? value) async {
    if (value != null) return _setDouble(PreferKey.readerFooterOffset, value);
    final prefs = await SharedPreferences.getInstance();
    _ensureSaved(
      PreferKey.readerFooterOffset,
      await prefs.remove(PreferKey.readerFooterOffset),
    );
  }

  Future<void> saveHideStatusBar(bool value) {
    return _setBool(PreferKey.readerHideStatusBar, value);
  }

  Future<void> saveHeaderInfo(ReaderV2InfoSlots value) {
    return _setString(PreferKey.readerHeaderInfo, value.encode());
  }

  Future<void> saveFooterInfo(ReaderV2InfoSlots value) {
    return _setString(PreferKey.readerFooterInfo, value.encode());
  }

  Future<void> saveHighlightColor(ReaderV2HighlightColor value) {
    return _setString(PreferKey.readerHighlightColor, value.name);
  }

  Future<void> saveHighlightStrength(double value) {
    return _setDouble(
      PreferKey.readerHighlightStrength,
      ReaderV2HighlightStrength.normalize(value),
    );
  }

  List<int> parseClickActions(String? stored) {
    return _parseClickActions(stored);
  }

  List<int> normalizeClickActions(List<int> actions) {
    return _normalizeClickActions(actions);
  }

  Future<void> _setDouble(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    _ensureSaved(key, await prefs.setDouble(key, value));
  }

  Future<void> _setInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    _ensureSaved(key, await prefs.setInt(key, value));
  }

  Future<void> _setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    _ensureSaved(key, await prefs.setBool(key, value));
  }

  Future<void> _setString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    _ensureSaved(key, await prefs.setString(key, value));
  }

  void _ensureSaved(String key, bool saved) {
    if (!saved) throw StateError('SharedPreferences rejected $key');
  }

  List<int> _parseClickActions(String? stored) {
    final normalized =
        stored
            ?.split(',')
            .map((value) => int.tryParse(value.trim()))
            .whereType<int>()
            .toList();
    return _normalizeClickActions(normalized);
  }

  List<int> _normalizeClickActions(List<int>? actions) {
    if (actions == null || actions.length != 9) {
      return ReaderV2TapAction.defaultGrid();
    }
    return List<int>.from(actions);
  }

  double _normalizePagePadding(double? value, double fallback) {
    if (value == null || !value.isFinite) return fallback;
    return value.clamp(minPagePadding, maxPagePadding).toDouble();
  }

  double? _normalizeOptionalPagePadding(double? value) {
    if (value == null || !value.isFinite) return null;
    return value.clamp(minPagePadding, maxPagePadding).toDouble();
  }

  double _normalizeChapterSpacing(double? value, double fallback) {
    if (value == null || !value.isFinite) return fallback;
    return value.clamp(minChapterSpacing, maxChapterSpacing).toDouble();
  }

  double _normalizeAutoPageSpeed(double? value) {
    if (value == null || !value.isFinite)
      return ReaderV2PrefsSnapshot.defaults().autoPageSpeed;
    if (value > 1) {
      return (value / 100).clamp(minAutoPageSpeed, maxAutoPageSpeed).toDouble();
    }
    return value.clamp(minAutoPageSpeed, maxAutoPageSpeed).toDouble();
  }
}
