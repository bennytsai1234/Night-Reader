import 'dart:async';

import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/reader_v2/features/brightness/reader_v2_brightness.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_tap_action.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_highlight_style.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_info_item.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_orientation.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_page_turn_speed.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
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

  /// 左右對齊：一行湊不滿一個字格的空隙攤進字距，正文左右兩緣貼齊邊距。
  final bool justifyText;

  /// 正文與頁首之間的距離（px）；隱藏狀態列時從鏡頭挖孔下緣算起。
  final double paddingTop;

  /// 正文與頁尾資訊列之間的距離（px）；沒有頁尾時與畫面底部之間。
  final double paddingBottom;

  /// 頁尾資訊列底部到畫面底部的距離（px）。
  final double footerOffset;

  /// 閱讀時隱藏系統狀態列（時間、訊號、電量）。
  final bool hideStatusBar;
  final ReaderV2InfoSlots headerInfo;
  final ReaderV2InfoSlots footerInfo;

  /// 朗讀高亮與選字反白的顏色，以及朗讀高亮的深淺。
  final ReaderV2HighlightColor highlightColor;
  final double highlightStrength;

  /// 亮度跟隨系統；關閉時用 [brightness]。
  final bool brightnessAuto;

  /// 亮度條的位置（0–1），換算見 [ReaderV2Brightness]。
  final double brightness;

  /// 音量鍵翻頁：音量下是下一頁、音量上是上一頁；[volumeKeyReversed] 時對調。
  final bool volumeKeyPage;
  final bool volumeKeyReversed;

  /// 章節標題與正文之間的空白（行）。
  final double titleSpacing;

  /// 閱讀器露在畫面上時螢幕保持常亮。
  final bool keepScreenOn;
  final ReaderV2Orientation orientation;

  /// 隱藏狀態列時一起隱藏系統導覽列；[hideStatusBar] 關著時不起作用。
  final bool hideNavigationBar;

  /// 翻頁時上一屏留在畫面上的行數，與捲過一屏的快慢。
  final int pageTurnOverlap;
  final ReaderV2PageTurnSpeed pageTurnSpeed;

  /// 頁首頁尾的時間用 24 小時制；全書進度顯示到小數第幾位。
  final bool use24HourClock;
  final int progressFractionDigits;

  /// 亮度條拉到底時疊上的黑色不透明度。
  final double maxDim;

  /// 正文上下緣漸隱的最大高度（px）；0 是不漸隱。
  final double edgeFade;

  /// 朗讀時畫面跟著念到的句子捲動。
  final bool ttsFollow;

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
    required this.justifyText,
    required this.paddingTop,
    required this.paddingBottom,
    required this.footerOffset,
    required this.hideStatusBar,
    required this.headerInfo,
    required this.footerInfo,
    required this.highlightColor,
    required this.highlightStrength,
    required this.brightnessAuto,
    required this.brightness,
    required this.volumeKeyPage,
    required this.volumeKeyReversed,
    required this.titleSpacing,
    required this.keepScreenOn,
    required this.orientation,
    required this.hideNavigationBar,
    required this.pageTurnOverlap,
    required this.pageTurnSpeed,
    required this.use24HourClock,
    required this.progressFractionDigits,
    required this.maxDim,
    required this.edgeFade,
    required this.ttsFollow,
  });

  factory ReaderV2PrefsSnapshot.defaults() {
    return ReaderV2PrefsSnapshot(
      fontSize: 18.0,
      titleFontSize: 18.0 + kReaderV2DefaultTitleSizeDelta,
      // 排版與邊距的預設照使用者自己讀書用的設定（2026-10-15）。
      lineHeight: 1.4,
      paragraphSpacing: 0.0,
      chapterSpacing: 0.5,
      letterSpacing: 0.2,
      textIndent: 2,
      autoPageSpeed: 0.16,
      chineseConvert: 0,
      showAddToShelfAlert: true,
      clickActions: ReaderV2TapAction.defaultGrid(),
      paddingHorizontal: 12.0,
      justifyText: true,
      paddingTop: 0.0,
      paddingBottom: 4.0,
      footerOffset: 4.0,
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
      brightnessAuto: true,
      brightness: ReaderV2Brightness.defaultLevel,
      volumeKeyPage: false,
      volumeKeyReversed: false,
      titleSpacing: 0.0,
      keepScreenOn: true,
      orientation: ReaderV2Orientation.system,
      hideNavigationBar: false,
      pageTurnOverlap: 1,
      pageTurnSpeed: ReaderV2PageTurnSpeed.normal,
      use24HourClock: true,
      progressFractionDigits: 1,
      maxDim: ReaderV2Brightness.defaultMaxDim,
      edgeFade: ReaderV2PrefsRepository.defaultEdgeFade,
      ttsFollow: true,
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
    bool? justifyText,
    double? paddingTop,
    double? paddingBottom,
    double? footerOffset,
    bool? hideStatusBar,
    ReaderV2InfoSlots? headerInfo,
    ReaderV2InfoSlots? footerInfo,
    ReaderV2HighlightColor? highlightColor,
    double? highlightStrength,
    bool? brightnessAuto,
    double? brightness,
    bool? volumeKeyPage,
    bool? volumeKeyReversed,
    double? titleSpacing,
    bool? keepScreenOn,
    ReaderV2Orientation? orientation,
    bool? hideNavigationBar,
    int? pageTurnOverlap,
    ReaderV2PageTurnSpeed? pageTurnSpeed,
    bool? use24HourClock,
    int? progressFractionDigits,
    double? maxDim,
    double? edgeFade,
    bool? ttsFollow,
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
      justifyText: justifyText ?? this.justifyText,
      paddingTop: paddingTop ?? this.paddingTop,
      paddingBottom: paddingBottom ?? this.paddingBottom,
      footerOffset: footerOffset ?? this.footerOffset,
      hideStatusBar: hideStatusBar ?? this.hideStatusBar,
      headerInfo: headerInfo ?? this.headerInfo,
      footerInfo: footerInfo ?? this.footerInfo,
      highlightColor: highlightColor ?? this.highlightColor,
      highlightStrength: highlightStrength ?? this.highlightStrength,
      brightnessAuto: brightnessAuto ?? this.brightnessAuto,
      brightness: brightness ?? this.brightness,
      volumeKeyPage: volumeKeyPage ?? this.volumeKeyPage,
      volumeKeyReversed: volumeKeyReversed ?? this.volumeKeyReversed,
      titleSpacing: titleSpacing ?? this.titleSpacing,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      orientation: orientation ?? this.orientation,
      hideNavigationBar: hideNavigationBar ?? this.hideNavigationBar,
      pageTurnOverlap: pageTurnOverlap ?? this.pageTurnOverlap,
      pageTurnSpeed: pageTurnSpeed ?? this.pageTurnSpeed,
      use24HourClock: use24HourClock ?? this.use24HourClock,
      progressFractionDigits:
          progressFractionDigits ?? this.progressFractionDigits,
      maxDim: maxDim ?? this.maxDim,
      edgeFade: edgeFade ?? this.edgeFade,
      ttsFollow: ttsFollow ?? this.ttsFollow,
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

  /// 標題間距的合法範圍（行）。
  static const double minTitleSpacing = 0.0;
  static const double maxTitleSpacing = 3.0;

  /// 翻頁保留行數的合法範圍。
  static const int minPageTurnOverlap = 0;
  static const int maxPageTurnOverlap = 3;

  /// 全書進度最多顯示到小數第一位：進度快照只在千分之一的變化時通知，
  /// 第二位不會跟著更新。
  static const int maxProgressFractionDigits = 1;

  /// 正文上下緣漸隱的合法範圍（px）；預設同 App 頁首下緣的漸隱。
  static const double minEdgeFade = 0.0;
  static const double maxEdgeFade = 24.0;
  static const double defaultEdgeFade = 14.0;

  Future<ReaderV2PrefsSnapshot> load() async =>
      read(await SharedPreferences.getInstance());

  /// 還沒有標題間距這個設定時，把從字號、行高與段距換算出的值存下來；之後
  /// 改這三項，標題間距不會跟著變。[SharedPreferences] 的快取同步更新，
  /// 接著的 [read] 就讀得到。
  void migrate(SharedPreferences prefs) {
    if (prefs.containsKey(PreferKey.readerTitleSpacing)) return;
    unawaited(
      prefs.setDouble(PreferKey.readerTitleSpacing, read(prefs).titleSpacing),
    );
  }

  /// 從已經取得的 [SharedPreferences] 同步讀出設定。
  ReaderV2PrefsSnapshot read(SharedPreferences prefs) {
    final defaults = ReaderV2PrefsSnapshot.defaults();
    final fontSize =
        prefs.getDouble(PreferKey.readerFontSize) ?? defaults.fontSize;
    final lineHeight =
        prefs.getDouble(PreferKey.readerLineHeight) ?? defaults.lineHeight;
    final paragraphSpacing =
        prefs.getDouble(PreferKey.readerParagraphSpacing) ??
        defaults.paragraphSpacing;
    return ReaderV2PrefsSnapshot(
      fontSize: fontSize,
      titleFontSize:
          prefs.getDouble(PreferKey.readerTitleFontSize) ??
          fontSize + kReaderV2DefaultTitleSizeDelta,
      lineHeight: lineHeight,
      paragraphSpacing: paragraphSpacing,
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
      justifyText:
          prefs.getBool(PreferKey.readerJustifyText) ?? defaults.justifyText,
      paddingTop: _normalizePagePadding(
        prefs.getDouble(PreferKey.readerPaddingTop),
        defaults.paddingTop,
      ),
      paddingBottom: _normalizePagePadding(
        prefs.getDouble(PreferKey.readerPaddingBottom),
        defaults.paddingBottom,
      ),
      footerOffset: _normalizePagePadding(
        prefs.getDouble(PreferKey.readerFooterOffset),
        defaults.footerOffset,
      ),
      hideStatusBar:
          prefs.getBool(PreferKey.readerHideStatusBar) ??
          defaults.hideStatusBar,
      headerInfo:
          ReaderV2InfoSlots.decode(
            prefs.getString(PreferKey.readerHeaderInfo),
          ) ??
          defaults.headerInfo,
      footerInfo:
          ReaderV2InfoSlots.decode(
            prefs.getString(PreferKey.readerFooterInfo),
          ) ??
          defaults.footerInfo,
      highlightColor: ReaderV2HighlightColor.parse(
        prefs.getString(PreferKey.readerHighlightColor),
      ),
      highlightStrength: ReaderV2HighlightStrength.normalize(
        prefs.getDouble(PreferKey.readerHighlightStrength),
      ),
      brightnessAuto:
          prefs.getBool(PreferKey.readerBrightnessAuto) ??
          defaults.brightnessAuto,
      brightness: ReaderV2Brightness.normalize(
        prefs.getDouble(PreferKey.readerBrightness),
      ),
      volumeKeyPage:
          prefs.getBool(PreferKey.readerVolumeKeyPage) ??
          defaults.volumeKeyPage,
      volumeKeyReversed:
          prefs.getBool(PreferKey.readerVolumeKeyReversed) ??
          defaults.volumeKeyReversed,
      titleSpacing: _normalizeTitleSpacing(
        prefs.getDouble(PreferKey.readerTitleSpacing) ??
            _legacyTitleSpacing(
              fontSize: fontSize,
              lineHeight: lineHeight,
              paragraphSpacing: paragraphSpacing,
            ),
      ),
      keepScreenOn:
          prefs.getBool(PreferKey.readerKeepScreenOn) ?? defaults.keepScreenOn,
      orientation: ReaderV2Orientation.parse(
        prefs.getString(PreferKey.readerOrientation),
      ),
      hideNavigationBar:
          prefs.getBool(PreferKey.readerHideNavigationBar) ??
          defaults.hideNavigationBar,
      pageTurnOverlap: normalizePageTurnOverlap(
        prefs.getInt(PreferKey.readerPageTurnOverlap) ??
            defaults.pageTurnOverlap,
      ),
      pageTurnSpeed: ReaderV2PageTurnSpeed.parse(
        prefs.getString(PreferKey.readerPageTurnSpeed),
      ),
      use24HourClock:
          prefs.getBool(PreferKey.readerUse24HourClock) ??
          defaults.use24HourClock,
      progressFractionDigits: normalizeProgressFractionDigits(
        prefs.getInt(PreferKey.readerProgressFractionDigits) ??
            defaults.progressFractionDigits,
      ),
      maxDim: ReaderV2Brightness.normalizeMaxDim(
        prefs.getDouble(PreferKey.readerMaxDim),
      ),
      edgeFade: normalizeEdgeFade(prefs.getDouble(PreferKey.readerEdgeFade)),
      ttsFollow: prefs.getBool(PreferKey.readerTtsFollow) ?? defaults.ttsFollow,
    );
  }

  /// 還沒有標題間距這個設定時，標題下方留的是段距 × 8（px）；換算成行，
  /// 升級後版面不變。存完整精度，不先對齊步進的 0.1 行（那會讓留白變多
  /// 或變少，段距很小時甚至變成 0）；讀者動到這一欄時步進器才對齊格點。
  static double _legacyTitleSpacing({
    required double fontSize,
    required double lineHeight,
    required double paragraphSpacing,
  }) {
    final lineExtent = fontSize * ReaderV2Style.normalizeLineHeight(lineHeight);
    if (!paragraphSpacing.isFinite || lineExtent <= 0) return 0.0;
    return paragraphSpacing * 8 / lineExtent;
  }

  static double _normalizeTitleSpacing(double value) {
    if (!value.isFinite) return ReaderV2PrefsSnapshot.defaults().titleSpacing;
    return value.clamp(minTitleSpacing, maxTitleSpacing).toDouble();
  }

  static int normalizePageTurnOverlap(int value) =>
      value.clamp(minPageTurnOverlap, maxPageTurnOverlap);

  static int normalizeProgressFractionDigits(int value) =>
      value.clamp(0, maxProgressFractionDigits);

  static double normalizeEdgeFade(double? value) {
    if (value == null || !value.isFinite) return defaultEdgeFade;
    return value.clamp(minEdgeFade, maxEdgeFade).toDouble();
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

  Future<void> saveFooterOffset(double value) {
    return _setDouble(PreferKey.readerFooterOffset, value);
  }

  Future<void> saveJustifyText(bool value) {
    return _setBool(PreferKey.readerJustifyText, value);
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

  Future<void> saveBrightnessAuto(bool value) {
    return _setBool(PreferKey.readerBrightnessAuto, value);
  }

  Future<void> saveBrightness(double value) {
    return _setDouble(
      PreferKey.readerBrightness,
      ReaderV2Brightness.normalize(value),
    );
  }

  Future<void> saveVolumeKeyPage(bool value) {
    return _setBool(PreferKey.readerVolumeKeyPage, value);
  }

  Future<void> saveVolumeKeyReversed(bool value) {
    return _setBool(PreferKey.readerVolumeKeyReversed, value);
  }

  Future<void> saveTitleSpacing(double value) {
    return _setDouble(PreferKey.readerTitleSpacing, value);
  }

  Future<void> saveKeepScreenOn(bool value) {
    return _setBool(PreferKey.readerKeepScreenOn, value);
  }

  Future<void> saveOrientation(ReaderV2Orientation value) {
    return _setString(PreferKey.readerOrientation, value.name);
  }

  Future<void> saveHideNavigationBar(bool value) {
    return _setBool(PreferKey.readerHideNavigationBar, value);
  }

  Future<void> savePageTurnOverlap(int value) {
    return _setInt(PreferKey.readerPageTurnOverlap, value);
  }

  Future<void> savePageTurnSpeed(ReaderV2PageTurnSpeed value) {
    return _setString(PreferKey.readerPageTurnSpeed, value.name);
  }

  Future<void> saveUse24HourClock(bool value) {
    return _setBool(PreferKey.readerUse24HourClock, value);
  }

  Future<void> saveProgressFractionDigits(int value) {
    return _setInt(PreferKey.readerProgressFractionDigits, value);
  }

  Future<void> saveMaxDim(double value) {
    return _setDouble(PreferKey.readerMaxDim, value);
  }

  Future<void> saveEdgeFade(double value) {
    return _setDouble(PreferKey.readerEdgeFade, value);
  }

  Future<void> saveTtsFollow(bool value) {
    return _setBool(PreferKey.readerTtsFollow, value);
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
    final normalized = stored
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

  double _normalizeChapterSpacing(double? value, double fallback) {
    if (value == null || !value.isFinite) return fallback;
    return value.clamp(minChapterSpacing, maxChapterSpacing).toDouble();
  }

  double _normalizeAutoPageSpeed(double? value) {
    if (value == null || !value.isFinite) {
      return ReaderV2PrefsSnapshot.defaults().autoPageSpeed;
    }
    if (value > 1) {
      return (value / 100).clamp(minAutoPageSpeed, maxAutoPageSpeed).toDouble();
    }
    return value.clamp(minAutoPageSpeed, maxAutoPageSpeed).toDouble();
  }
}
