import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_tap_action.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_info_item.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReaderV2PrefsSnapshot {
  final double fontSize;

  /// 章節標題字號。未保存過時沿用舊版規則（正文 + 4），外觀不變。
  final double titleFontSize;
  final double lineHeight;
  final double paragraphSpacing;
  final double letterSpacing;
  final int textIndent;
  final int themeIndex;
  final int lastDayThemeIndex;
  final int lastNightThemeIndex;
  final int menuThemeIndex;
  final double autoPageSpeed;
  final int chineseConvert;
  final bool showAddToShelfAlert;
  final List<int> clickActions;

  /// 正文左右邊距（px）。
  final double paddingHorizontal;

  /// 正文與頁首、頁尾之間額外保留的空白（px）。
  final double paddingTop;
  final double paddingBottom;

  /// 閱讀時隱藏系統狀態列（時間、訊號、電量）。
  final bool hideStatusBar;
  final ReaderV2InfoSlots headerInfo;
  final ReaderV2InfoSlots footerInfo;

  const ReaderV2PrefsSnapshot({
    required this.fontSize,
    required this.titleFontSize,
    required this.lineHeight,
    required this.paragraphSpacing,
    required this.letterSpacing,
    required this.textIndent,
    required this.themeIndex,
    required this.lastDayThemeIndex,
    required this.lastNightThemeIndex,
    required this.menuThemeIndex,
    required this.autoPageSpeed,
    required this.chineseConvert,
    required this.showAddToShelfAlert,
    required this.clickActions,
    required this.paddingHorizontal,
    required this.paddingTop,
    required this.paddingBottom,
    required this.hideStatusBar,
    required this.headerInfo,
    required this.footerInfo,
  });

  factory ReaderV2PrefsSnapshot.defaults() {
    return ReaderV2PrefsSnapshot(
      fontSize: 18.0,
      titleFontSize: 18.0 + kReaderV2DefaultTitleSizeDelta,
      lineHeight: 1.5,
      paragraphSpacing: 1.0,
      letterSpacing: 0.0,
      textIndent: 2,
      themeIndex: 0,
      lastDayThemeIndex: 0,
      lastNightThemeIndex: 1,
      menuThemeIndex: 0,
      autoPageSpeed: 0.16,
      chineseConvert: 0,
      showAddToShelfAlert: true,
      clickActions: ReaderV2TapAction.defaultGrid(),
      paddingHorizontal: 16.0,
      paddingTop: 0.0,
      paddingBottom: 0.0,
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
    );
  }

  ReaderV2PrefsSnapshot copyWith({
    double? fontSize,
    double? titleFontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? letterSpacing,
    int? textIndent,
    int? themeIndex,
    int? lastDayThemeIndex,
    int? lastNightThemeIndex,
    int? menuThemeIndex,
    double? autoPageSpeed,
    int? chineseConvert,
    bool? showAddToShelfAlert,
    List<int>? clickActions,
    double? paddingHorizontal,
    double? paddingTop,
    double? paddingBottom,
    bool? hideStatusBar,
    ReaderV2InfoSlots? headerInfo,
    ReaderV2InfoSlots? footerInfo,
  }) {
    return ReaderV2PrefsSnapshot(
      fontSize: fontSize ?? this.fontSize,
      titleFontSize: titleFontSize ?? this.titleFontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      textIndent: textIndent ?? this.textIndent,
      themeIndex: themeIndex ?? this.themeIndex,
      lastDayThemeIndex: lastDayThemeIndex ?? this.lastDayThemeIndex,
      lastNightThemeIndex: lastNightThemeIndex ?? this.lastNightThemeIndex,
      menuThemeIndex: menuThemeIndex ?? this.menuThemeIndex,
      autoPageSpeed: autoPageSpeed ?? this.autoPageSpeed,
      chineseConvert: chineseConvert ?? this.chineseConvert,
      showAddToShelfAlert: showAddToShelfAlert ?? this.showAddToShelfAlert,
      clickActions: clickActions ?? List<int>.from(this.clickActions),
      paddingHorizontal: paddingHorizontal ?? this.paddingHorizontal,
      paddingTop: paddingTop ?? this.paddingTop,
      paddingBottom: paddingBottom ?? this.paddingBottom,
      hideStatusBar: hideStatusBar ?? this.hideStatusBar,
      headerInfo: headerInfo ?? this.headerInfo,
      footerInfo: footerInfo ?? this.footerInfo,
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

  static ReaderV2PrefsSnapshot? _latestSnapshot;

  static ReaderV2PrefsSnapshot get cachedSnapshot =>
      _latestSnapshot ?? ReaderV2PrefsSnapshot.defaults();

  Future<ReaderV2PrefsSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final defaults = ReaderV2PrefsSnapshot.defaults();
    final themeIndex =
        prefs.getInt(PreferKey.readerThemeIndex) ?? defaults.themeIndex;
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
      letterSpacing:
          prefs.getDouble(PreferKey.readerLetterSpacing) ??
          defaults.letterSpacing,
      textIndent:
          prefs.getInt(PreferKey.readerTextIndent) ?? defaults.textIndent,
      themeIndex: themeIndex,
      lastDayThemeIndex:
          prefs.getInt(PreferKey.readerDayThemeIndex) ??
          defaults.lastDayThemeIndex,
      lastNightThemeIndex:
          prefs.getInt(PreferKey.readerNightThemeIndex) ??
          defaults.lastNightThemeIndex,
      menuThemeIndex:
          prefs.getInt(PreferKey.readerMenuThemeIndex) ?? themeIndex,
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
      hideStatusBar:
          prefs.getBool(PreferKey.readerHideStatusBar) ?? defaults.hideStatusBar,
      headerInfo:
          ReaderV2InfoSlots.decode(prefs.getString(PreferKey.readerHeaderInfo)) ??
          defaults.headerInfo,
      footerInfo:
          ReaderV2InfoSlots.decode(prefs.getString(PreferKey.readerFooterInfo)) ??
          defaults.footerInfo,
    );
    _latestSnapshot = snapshot;
    return snapshot;
  }

  Future<void> saveFontSize(double value) {
    return _saveAndCache(
      () => _setDouble(PreferKey.readerFontSize, value),
      (snapshot) => snapshot.copyWith(fontSize: value),
    );
  }

  Future<void> saveTitleFontSize(double value) {
    return _saveAndCache(
      () => _setDouble(PreferKey.readerTitleFontSize, value),
      (snapshot) => snapshot.copyWith(titleFontSize: value),
    );
  }

  Future<void> saveLineHeight(double value) {
    return _saveAndCache(
      () => _setDouble(PreferKey.readerLineHeight, value),
      (snapshot) => snapshot.copyWith(lineHeight: value),
    );
  }

  Future<void> saveParagraphSpacing(double value) {
    return _saveAndCache(
      () => _setDouble(PreferKey.readerParagraphSpacing, value),
      (snapshot) => snapshot.copyWith(paragraphSpacing: value),
    );
  }

  Future<void> saveLetterSpacing(double value) {
    return _saveAndCache(
      () => _setDouble(PreferKey.readerLetterSpacing, value),
      (snapshot) => snapshot.copyWith(letterSpacing: value),
    );
  }

  Future<void> saveTextIndent(int value) {
    return _saveAndCache(
      () => _setInt(PreferKey.readerTextIndent, value),
      (snapshot) => snapshot.copyWith(textIndent: value),
    );
  }

  Future<void> saveThemeIndex(int value) {
    return _saveAndCache(
      () => _setInt(PreferKey.readerThemeIndex, value),
      (snapshot) => snapshot.copyWith(themeIndex: value),
    );
  }

  Future<void> saveDayThemeIndex(int value) {
    return _saveAndCache(
      () => _setInt(PreferKey.readerDayThemeIndex, value),
      (snapshot) => snapshot.copyWith(lastDayThemeIndex: value),
    );
  }

  Future<void> saveNightThemeIndex(int value) {
    return _saveAndCache(
      () => _setInt(PreferKey.readerNightThemeIndex, value),
      (snapshot) => snapshot.copyWith(lastNightThemeIndex: value),
    );
  }

  Future<void> saveMenuThemeIndex(int value) {
    return _saveAndCache(
      () => _setInt(PreferKey.readerMenuThemeIndex, value),
      (snapshot) => snapshot.copyWith(menuThemeIndex: value),
    );
  }

  Future<void> saveAutoPageSpeed(double value) {
    final normalized = _normalizeAutoPageSpeed(value);
    return _saveAndCache(
      () => _setDouble(PreferKey.readerAutoPageSpeed, normalized),
      (snapshot) => snapshot.copyWith(autoPageSpeed: normalized),
    );
  }

  Future<void> saveChineseConvert(int value) {
    return _saveAndCache(
      () => _setInt(PreferKey.readerChineseConvert, value),
      (snapshot) => snapshot.copyWith(chineseConvert: value),
    );
  }

  Future<void> saveShowAddToShelfAlert(bool value) {
    return _saveAndCache(
      () => _setBool(PreferKey.showAddToShelfAlert, value),
      (snapshot) => snapshot.copyWith(showAddToShelfAlert: value),
    );
  }

  Future<void> saveClickActions(List<int> actions) {
    final normalized = _normalizeClickActions(actions);
    return _saveAndCache(
      () => _setString(PreferKey.readerClickActions, normalized.join(',')),
      (snapshot) => snapshot.copyWith(clickActions: normalized),
    );
  }

  Future<void> savePaddingHorizontal(double value) {
    return _saveAndCache(
      () => _setDouble(PreferKey.readerPaddingHorizontal, value),
      (snapshot) => snapshot.copyWith(paddingHorizontal: value),
    );
  }

  Future<void> savePaddingTop(double value) {
    return _saveAndCache(
      () => _setDouble(PreferKey.readerPaddingTop, value),
      (snapshot) => snapshot.copyWith(paddingTop: value),
    );
  }

  Future<void> savePaddingBottom(double value) {
    return _saveAndCache(
      () => _setDouble(PreferKey.readerPaddingBottom, value),
      (snapshot) => snapshot.copyWith(paddingBottom: value),
    );
  }

  Future<void> saveHideStatusBar(bool value) {
    return _saveAndCache(
      () => _setBool(PreferKey.readerHideStatusBar, value),
      (snapshot) => snapshot.copyWith(hideStatusBar: value),
    );
  }

  Future<void> saveHeaderInfo(ReaderV2InfoSlots value) {
    return _saveAndCache(
      () => _setString(PreferKey.readerHeaderInfo, value.encode()),
      (snapshot) => snapshot.copyWith(headerInfo: value),
    );
  }

  Future<void> saveFooterInfo(ReaderV2InfoSlots value) {
    return _saveAndCache(
      () => _setString(PreferKey.readerFooterInfo, value.encode()),
      (snapshot) => snapshot.copyWith(footerInfo: value),
    );
  }

  Future<void> _saveAndCache(
    Future<void> Function() persist,
    ReaderV2PrefsSnapshot Function(ReaderV2PrefsSnapshot snapshot) update,
  ) async {
    await persist();
    final latest = _latestSnapshot;
    if (latest != null) {
      _latestSnapshot = update(latest);
    }
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

  double _normalizeAutoPageSpeed(double? value) {
    if (value == null || !value.isFinite)
      return ReaderV2PrefsSnapshot.defaults().autoPageSpeed;
    if (value > 1) {
      return (value / 100).clamp(minAutoPageSpeed, maxAutoPageSpeed).toDouble();
    }
    return value.clamp(minAutoPageSpeed, maxAutoPageSpeed).toDouble();
  }
}
