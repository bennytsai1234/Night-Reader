import 'dart:async';

import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/fonts/app_font.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_constants.dart';
import 'package:night_reader/features/reader_v2/features/brightness/reader_v2_brightness.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_tap_action.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_highlight_style.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_info_item.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_orientation.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_page_turn_speed.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一個閱讀設定的存檔描述：存檔名稱、預設值，以及讀出與寫入的方式。
///
/// [key] 是存檔名稱，多台手機同步與備份靠它對上（ADR 0039），不能改。
final class ReaderV2Setting<T> {
  ReaderV2Setting._({
    required this.key,
    required this._fallback,
    required this._read,
    required this._decode,
    required this._prepare,
  });

  final String key;
  final T Function() _fallback;
  final T? Function(SharedPreferences prefs) _read;
  final T Function(T? stored) _decode;
  final ReaderV2SettingWrite Function(T value) _prepare;

  /// 預設值。每次都是新的物件，清單不在快照之間共用。
  T get fallback => _fallback();

  /// 從 [prefs] 讀出：沒有值的用預設值，讀到的值照 [_decode] 修正到合法範圍。
  T read(SharedPreferences prefs) => _decode(_read(prefs));

  /// 把 [value] 轉成要存的樣子（在呼叫的當下，之後清單再被改也不影響），
  /// 回傳拿到偏好設定後寫入的那一步。
  ReaderV2SettingWrite prepare(T value) => _prepare(value);
}

/// 拿到偏好設定後寫入一個已經轉好的值；寫不進去時回傳 false。
typedef ReaderV2SettingWrite = Future<bool> Function(SharedPreferences prefs);

ReaderV2Setting<T> _setting<T>(
  String key,
  T Function() fallback, {
  required T? Function(SharedPreferences prefs) read,
  required ReaderV2SettingWrite Function(T value) prepare,
  T Function(T? stored)? decode,
}) {
  return ReaderV2Setting<T>._(
    key: key,
    fallback: fallback,
    read: read,
    decode: decode ?? ((T? stored) => stored ?? fallback()),
    prepare: prepare,
  );
}

ReaderV2Setting<double> _double(
  String key,
  double fallback, {
  double? Function(SharedPreferences prefs)? read,
  double Function(double? stored)? decode,
  double Function(double value)? encode,
}) {
  return _setting<double>(
    key,
    () => fallback,
    read: read ?? ((prefs) => prefs.getDouble(key)),
    decode: decode,
    prepare: (value) {
      final stored = encode == null ? value : encode(value);
      return (prefs) => prefs.setDouble(key, stored);
    },
  );
}

ReaderV2Setting<int> _int(
  String key,
  int fallback, {
  int Function(int? stored)? decode,
  int Function(int value)? encode,
}) {
  return _setting<int>(
    key,
    () => fallback,
    read: (prefs) => prefs.getInt(key),
    decode: decode,
    prepare: (value) {
      final stored = encode == null ? value : encode(value);
      return (prefs) => prefs.setInt(key, stored);
    },
  );
}

ReaderV2Setting<bool> _bool(String key, bool fallback) {
  return _setting<bool>(
    key,
    () => fallback,
    read: (prefs) => prefs.getBool(key),
    prepare: (value) =>
        (prefs) => prefs.setBool(key, value),
  );
}

/// 字串存檔的設定：[parse] 讀不懂時回傳 null，就用預設值。
ReaderV2Setting<T> _text<T>(
  String key,
  T Function() fallback, {
  required T? Function(String? stored) parse,
  required String Function(T value) encode,
}) {
  return _setting<T>(
    key,
    fallback,
    read: (prefs) => parse(prefs.getString(key)),
    prepare: (value) {
      final stored = encode(value);
      return (prefs) => prefs.setString(key, stored);
    },
  );
}

/// 有限的數值夾在 [min]～[max]；沒有值或不是有限的數（NaN、無限大）就用 [fallback]。
double Function(double? stored) _finiteClamp(
  double min,
  double max,
  double fallback,
) {
  return (stored) => stored == null || !stored.isFinite
      ? fallback
      : stored.clamp(min, max).toDouble();
}

/// 正文與頁首頁尾的留白（px）。
ReaderV2Setting<double> _pagePadding(String key, double fallback) {
  return _double(
    key,
    fallback,
    decode: _finiteClamp(
      ReaderV2PrefsRepository.minPagePadding,
      ReaderV2PrefsRepository.maxPagePadding,
      fallback,
    ),
  );
}

const double _defaultFontSize = 18.0;
const double _defaultLineHeight = 1.4;
const double _defaultParagraphSpacing = 0.0;
const double _defaultAutoPageSpeed = 0.16;

/// 自動翻頁速度（每秒滾動畫面高的比例）。舊版存的是整數百分比，超過 1 就除以 100。
double _autoPageSpeedOf(double? value) {
  if (value == null || !value.isFinite) return _defaultAutoPageSpeed;
  const min = ReaderV2PrefsRepository.minAutoPageSpeed;
  const max = ReaderV2PrefsRepository.maxAutoPageSpeed;
  if (value > 1) return (value / 100).clamp(min, max).toDouble();
  return value.clamp(min, max).toDouble();
}

/// 還沒有標題間距這個設定時，標題下方留的是段距 × 8（px）；換算成行，
/// 升級後版面不變。存完整精度，不先對齊步進的 0.1 行（那會讓留白變多
/// 或變少，段距很小時甚至變成 0）；讀者動到這一欄時步進器才對齊格點。
double _legacyTitleSpacing({
  required double fontSize,
  required double lineHeight,
  required double paragraphSpacing,
}) {
  final lineExtent = fontSize * ReaderV2Style.normalizeLineHeight(lineHeight);
  if (!paragraphSpacing.isFinite || lineExtent <= 0) return 0.0;
  return paragraphSpacing * 8 / lineExtent;
}

/// 點擊九宮格的動作，存成逗號分隔的九個數字；不是九個就用預設。
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

/// 所有閱讀設定的存檔描述。改值、存檔、還原、讀出都照這裡。
///
/// 加一個設定：在這裡加一行並列入 [all]，在 [ReaderV2PrefsSnapshot] 加一個讀取的
/// getter，在控制器加一個 set 方法與欄位。存檔名稱一旦存出去就不能改。
abstract final class ReaderV2Settings {
  /// 正文字號。
  static final fontSize = _double(PreferKey.readerFontSize, _defaultFontSize);

  /// 章節標題字號。未保存過時沿用舊版規則（正文 + 4），外觀不變。
  static final titleFontSize = _double(
    PreferKey.readerTitleFontSize,
    _defaultFontSize + kReaderV2DefaultTitleSizeDelta,
    read: (prefs) =>
        prefs.getDouble(PreferKey.readerTitleFontSize) ??
        (prefs.getDouble(PreferKey.readerFontSize) ?? _defaultFontSize) +
            kReaderV2DefaultTitleSizeDelta,
  );

  /// 排版與邊距的預設照使用者自己讀書用的設定（2026-10-15）。
  static final lineHeight = _double(
    PreferKey.readerLineHeight,
    _defaultLineHeight,
  );
  static final paragraphSpacing = _double(
    PreferKey.readerParagraphSpacing,
    _defaultParagraphSpacing,
  );

  /// 章末與下一章標題之間的空白（行）。
  static final chapterSpacing = _double(
    PreferKey.readerChapterSpacing,
    0.5,
    decode: _finiteClamp(
      ReaderV2PrefsRepository.minChapterSpacing,
      ReaderV2PrefsRepository.maxChapterSpacing,
      0.5,
    ),
  );
  static final letterSpacing = _double(PreferKey.readerLetterSpacing, 0.2);
  static final textIndent = _int(PreferKey.readerTextIndent, 2);

  /// 自動翻頁速度（每秒滾動畫面高的比例）；還讀得到舊版的整數百分比。
  static final autoPageSpeed = _double(
    PreferKey.readerAutoPageSpeed,
    _defaultAutoPageSpeed,
    read: (prefs) =>
        prefs.getDouble(PreferKey.readerAutoPageSpeed) ??
        prefs.getInt(PreferKey.autoReadSpeed)?.toDouble(),
    decode: _autoPageSpeedOf,
    encode: _autoPageSpeedOf,
  );
  static final chineseConvert = _int(PreferKey.readerChineseConvert, 0);
  static final showAddToShelfAlert = _bool(PreferKey.showAddToShelfAlert, true);
  static final clickActions = _text<List<int>>(
    PreferKey.readerClickActions,
    ReaderV2TapAction.defaultGrid,
    parse: _parseClickActions,
    encode: (actions) => _normalizeClickActions(actions).join(','),
  );

  /// 正文兩側最少留白；實際的左右邊距照每行字數算。
  static final paddingHorizontal = _pagePadding(
    PreferKey.readerPaddingHorizontal,
    12.0,
  );

  /// 每行最多幾個字；畫面放得下更多時正文欄收窄置中。
  static final lineChars = _int(
    PreferKey.readerLineChars,
    32,
    decode: (stored) =>
        ReaderV2PrefsRepository.normalizeLineChars(stored ?? 32),
    encode: ReaderV2PrefsRepository.normalizeLineChars,
  );

  /// 左右對齊：一行湊不滿一個字格的空隙攤進字距。
  static final justifyText = _bool(PreferKey.readerJustifyText, true);

  /// 正文與頁首之間的距離（px）；隱藏狀態列時從鏡頭挖孔下緣算起。
  static final paddingTop = _pagePadding(PreferKey.readerPaddingTop, 0.0);

  /// 正文與頁尾資訊列之間的距離（px）；沒有頁尾時與畫面底部之間。
  static final paddingBottom = _pagePadding(PreferKey.readerPaddingBottom, 4.0);

  /// 頁尾資訊列底部到畫面底部的距離（px）。
  static final footerOffset = _pagePadding(PreferKey.readerFooterOffset, 4.0);

  /// 閱讀時隱藏系統狀態列（時間、訊號、電量）。
  static final hideStatusBar = _bool(PreferKey.readerHideStatusBar, false);

  /// 頁首預設關閉：狀態列顯示時多一條頁首只會重複系統時鐘；
  /// 隱藏狀態列後由使用者決定鏡頭那一行放什麼。
  static final headerInfo = _text<ReaderV2InfoSlots>(
    PreferKey.readerHeaderInfo,
    () => const ReaderV2InfoSlots(
      left: ReaderV2InfoItem.none,
      right: ReaderV2InfoItem.none,
    ),
    parse: ReaderV2InfoSlots.decode,
    encode: (value) => value.encode(),
  );
  static final footerInfo = _text<ReaderV2InfoSlots>(
    PreferKey.readerFooterInfo,
    () => const ReaderV2InfoSlots(
      left: ReaderV2InfoItem.chapterTitle,
      right: ReaderV2InfoItem.bookProgress,
    ),
    parse: ReaderV2InfoSlots.decode,
    encode: (value) => value.encode(),
  );

  /// 朗讀高亮與選字反白的顏色，以及朗讀高亮的深淺。
  static final highlightColor = _text<ReaderV2HighlightColor>(
    PreferKey.readerHighlightColor,
    () => ReaderV2HighlightColor.theme,
    parse: ReaderV2HighlightColor.parse,
    encode: (value) => value.name,
  );
  static final highlightStrength = _double(
    PreferKey.readerHighlightStrength,
    ReaderV2HighlightStrength.defaultValue,
    decode: ReaderV2HighlightStrength.normalize,
    encode: ReaderV2HighlightStrength.normalize,
  );

  /// 亮度跟隨系統；關閉時用 [brightness]。
  static final brightnessAuto = _bool(PreferKey.readerBrightnessAuto, true);

  /// 亮度條的位置（0–1），換算見 [ReaderV2Brightness]。
  static final brightness = _double(
    PreferKey.readerBrightness,
    ReaderV2Brightness.defaultLevel,
    decode: ReaderV2Brightness.normalize,
    encode: ReaderV2Brightness.normalize,
  );

  /// 音量鍵翻頁：音量下是下一頁、音量上是上一頁；[volumeKeyReversed] 時對調。
  static final volumeKeyPage = _bool(PreferKey.readerVolumeKeyPage, false);
  static final volumeKeyReversed = _bool(
    PreferKey.readerVolumeKeyReversed,
    false,
  );

  /// 章節標題與正文之間的空白（行）。還沒有這個設定時從字號、行高與段距換算。
  static final titleSpacing = _double(
    PreferKey.readerTitleSpacing,
    0.0,
    read: (prefs) =>
        prefs.getDouble(PreferKey.readerTitleSpacing) ??
        _legacyTitleSpacing(
          fontSize:
              prefs.getDouble(PreferKey.readerFontSize) ?? _defaultFontSize,
          lineHeight:
              prefs.getDouble(PreferKey.readerLineHeight) ?? _defaultLineHeight,
          paragraphSpacing:
              prefs.getDouble(PreferKey.readerParagraphSpacing) ??
              _defaultParagraphSpacing,
        ),
    decode: _finiteClamp(
      ReaderV2PrefsRepository.minTitleSpacing,
      ReaderV2PrefsRepository.maxTitleSpacing,
      0.0,
    ),
  );

  /// 閱讀器露在畫面上時螢幕保持常亮。
  static final keepScreenOn = _bool(PreferKey.readerKeepScreenOn, true);
  static final orientation = _text<ReaderV2Orientation>(
    PreferKey.readerOrientation,
    () => ReaderV2Orientation.system,
    parse: ReaderV2Orientation.parse,
    encode: (value) => value.name,
  );

  /// 隱藏狀態列時一起隱藏系統導覽列；[hideStatusBar] 關著時不起作用。
  static final hideNavigationBar = _bool(
    PreferKey.readerHideNavigationBar,
    false,
  );

  /// 翻頁時上一屏留在畫面上的行數，與捲過一屏的快慢。
  static final pageTurnOverlap = _int(
    PreferKey.readerPageTurnOverlap,
    1,
    decode: (stored) =>
        ReaderV2PrefsRepository.normalizePageTurnOverlap(stored ?? 1),
  );
  static final pageTurnSpeed = _text<ReaderV2PageTurnSpeed>(
    PreferKey.readerPageTurnSpeed,
    () => ReaderV2PageTurnSpeed.normal,
    parse: ReaderV2PageTurnSpeed.parse,
    encode: (value) => value.name,
  );

  /// 頁首頁尾的時間用 24 小時制；全書進度顯示到小數第幾位。
  static final use24HourClock = _bool(PreferKey.readerUse24HourClock, true);
  static final progressFractionDigits = _int(
    PreferKey.readerProgressFractionDigits,
    1,
    decode: (stored) =>
        ReaderV2PrefsRepository.normalizeProgressFractionDigits(stored ?? 1),
  );

  /// 亮度條拉到底時疊上的黑色不透明度。
  static final maxDim = _double(
    PreferKey.readerMaxDim,
    ReaderV2Brightness.defaultMaxDim,
    decode: ReaderV2Brightness.normalizeMaxDim,
  );

  /// 正文上下緣漸隱的最大高度（px）；0 是不漸隱。
  static final edgeFade = _double(
    PreferKey.readerEdgeFade,
    ReaderV2PrefsRepository.defaultEdgeFade,
    decode: ReaderV2PrefsRepository.normalizeEdgeFade,
  );

  /// 朗讀時畫面跟著念到的句子捲動。
  static final ttsFollow = _bool(PreferKey.readerTtsFollow, true);

  /// 正文加粗；章節標題加粗、置中。
  static final bodyBold = _bool(PreferKey.readerBodyBold, false);
  static final titleBold = _bool(PreferKey.readerTitleBold, true);
  static final titleCenter = _bool(PreferKey.readerTitleCenter, false);

  /// 頁首頁尾資訊的字級。
  static final infoFontSize = _double(
    PreferKey.readerInfoFontSize,
    kReaderInfoFontSize,
    decode: ReaderV2PrefsRepository.normalizeInfoFontSize,
    encode: ReaderV2PrefsRepository.normalizeInfoFontSize,
  );

  /// 正文、標題與頁首頁尾的字型（ADR 0045）。
  static final readerFont = _text<AppFont>(
    PreferKey.readerFont,
    () => AppFont.system,
    parse: AppFont.fromStorage,
    encode: (value) => value.id,
  );

  /// 全部設定；快照由這裡預設、讀出。
  static final List<ReaderV2Setting<dynamic>> all = [
    fontSize,
    titleFontSize,
    lineHeight,
    paragraphSpacing,
    chapterSpacing,
    letterSpacing,
    textIndent,
    autoPageSpeed,
    chineseConvert,
    showAddToShelfAlert,
    clickActions,
    paddingHorizontal,
    lineChars,
    justifyText,
    paddingTop,
    paddingBottom,
    footerOffset,
    hideStatusBar,
    headerInfo,
    footerInfo,
    highlightColor,
    highlightStrength,
    brightnessAuto,
    brightness,
    volumeKeyPage,
    volumeKeyReversed,
    titleSpacing,
    keepScreenOn,
    orientation,
    hideNavigationBar,
    pageTurnOverlap,
    pageTurnSpeed,
    use24HourClock,
    progressFractionDigits,
    maxDim,
    edgeFade,
    ttsFollow,
    bodyBold,
    titleBold,
    titleCenter,
    infoFontSize,
    readerFont,
  ];
}

/// 閱讀設定的一份快照：每個設定一個值（見 [ReaderV2Settings]）。
class ReaderV2PrefsSnapshot {
  ReaderV2PrefsSnapshot._(this._values);

  final Map<Object, Object?> _values;

  /// 所有設定的預設值。
  factory ReaderV2PrefsSnapshot.defaults() => ReaderV2PrefsSnapshot._({
    for (final setting in ReaderV2Settings.all) setting: setting.fallback,
  });

  /// [setting] 在這份快照裡的值。
  T valueOf<T>(ReaderV2Setting<T> setting) => _values[setting] as T;

  /// 其餘設定不變、只換掉 [setting] 的值的新快照。其餘的清單（九宮格）各自
  /// 複製一份，不和這份快照共用。
  ReaderV2PrefsSnapshot withValue<T>(ReaderV2Setting<T> setting, T value) =>
      ReaderV2PrefsSnapshot._({
        for (final MapEntry(:key, value: current) in _values.entries)
          key: current is List<int> ? List<int>.of(current) : current,
        setting: value,
      });

  double get fontSize => valueOf(ReaderV2Settings.fontSize);
  double get titleFontSize => valueOf(ReaderV2Settings.titleFontSize);
  double get lineHeight => valueOf(ReaderV2Settings.lineHeight);
  double get paragraphSpacing => valueOf(ReaderV2Settings.paragraphSpacing);
  double get chapterSpacing => valueOf(ReaderV2Settings.chapterSpacing);
  double get letterSpacing => valueOf(ReaderV2Settings.letterSpacing);
  int get textIndent => valueOf(ReaderV2Settings.textIndent);
  double get autoPageSpeed => valueOf(ReaderV2Settings.autoPageSpeed);
  int get chineseConvert => valueOf(ReaderV2Settings.chineseConvert);
  bool get showAddToShelfAlert => valueOf(ReaderV2Settings.showAddToShelfAlert);
  List<int> get clickActions => valueOf(ReaderV2Settings.clickActions);
  double get paddingHorizontal => valueOf(ReaderV2Settings.paddingHorizontal);
  int get lineChars => valueOf(ReaderV2Settings.lineChars);
  bool get justifyText => valueOf(ReaderV2Settings.justifyText);
  double get paddingTop => valueOf(ReaderV2Settings.paddingTop);
  double get paddingBottom => valueOf(ReaderV2Settings.paddingBottom);
  double get footerOffset => valueOf(ReaderV2Settings.footerOffset);
  bool get hideStatusBar => valueOf(ReaderV2Settings.hideStatusBar);
  ReaderV2InfoSlots get headerInfo => valueOf(ReaderV2Settings.headerInfo);
  ReaderV2InfoSlots get footerInfo => valueOf(ReaderV2Settings.footerInfo);
  ReaderV2HighlightColor get highlightColor =>
      valueOf(ReaderV2Settings.highlightColor);
  double get highlightStrength => valueOf(ReaderV2Settings.highlightStrength);
  bool get brightnessAuto => valueOf(ReaderV2Settings.brightnessAuto);
  double get brightness => valueOf(ReaderV2Settings.brightness);
  bool get volumeKeyPage => valueOf(ReaderV2Settings.volumeKeyPage);
  bool get volumeKeyReversed => valueOf(ReaderV2Settings.volumeKeyReversed);
  double get titleSpacing => valueOf(ReaderV2Settings.titleSpacing);
  bool get keepScreenOn => valueOf(ReaderV2Settings.keepScreenOn);
  ReaderV2Orientation get orientation => valueOf(ReaderV2Settings.orientation);
  bool get hideNavigationBar => valueOf(ReaderV2Settings.hideNavigationBar);
  int get pageTurnOverlap => valueOf(ReaderV2Settings.pageTurnOverlap);
  ReaderV2PageTurnSpeed get pageTurnSpeed =>
      valueOf(ReaderV2Settings.pageTurnSpeed);
  bool get use24HourClock => valueOf(ReaderV2Settings.use24HourClock);
  int get progressFractionDigits =>
      valueOf(ReaderV2Settings.progressFractionDigits);
  double get maxDim => valueOf(ReaderV2Settings.maxDim);
  double get edgeFade => valueOf(ReaderV2Settings.edgeFade);
  bool get ttsFollow => valueOf(ReaderV2Settings.ttsFollow);
  bool get bodyBold => valueOf(ReaderV2Settings.bodyBold);
  bool get titleBold => valueOf(ReaderV2Settings.titleBold);
  bool get titleCenter => valueOf(ReaderV2Settings.titleCenter);
  double get infoFontSize => valueOf(ReaderV2Settings.infoFontSize);
  AppFont get readerFont => valueOf(ReaderV2Settings.readerFont);
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

  /// 每行字數存得下的範圍；能調到多少還看畫面放得下幾個字。下限是 1：最大
  /// 字號、最大字距再加上最寬的最少留白時，手機上一行放不到 6 個字，步進
  /// 列給的每個數都要存得下。
  static const ({int min, int max}) lineCharsRange = (min: 1, max: 120);

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

  /// 頁首頁尾字級的範圍：小於 9 在手機上讀不出來，大於 16 就比常用的正文
  /// 還大。
  static const double minInfoFontSize = 9.0;
  static const double maxInfoFontSize = 16.0;

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
  ReaderV2PrefsSnapshot read(SharedPreferences prefs) =>
      ReaderV2PrefsSnapshot._({
        for (final setting in ReaderV2Settings.all)
          setting: setting.read(prefs),
      });

  /// 寫入一個設定；寫不進去時丟出錯誤，由控制器還原成最後落地的值。
  /// 存的是呼叫當下的值：清單在等偏好設定的期間又被改也不影響。
  Future<void> save<T>(ReaderV2Setting<T> setting, T value) async {
    final write = setting.prepare(value);
    final prefs = await SharedPreferences.getInstance();
    if (!await write(prefs)) {
      throw StateError('SharedPreferences rejected ${setting.key}');
    }
  }

  static int normalizePageTurnOverlap(int value) =>
      value.clamp(minPageTurnOverlap, maxPageTurnOverlap);

  static int normalizeProgressFractionDigits(int value) =>
      value.clamp(0, maxProgressFractionDigits);

  static double normalizeEdgeFade(double? value) {
    if (value == null || !value.isFinite) return defaultEdgeFade;
    return value.clamp(minEdgeFade, maxEdgeFade).toDouble();
  }

  static int normalizeLineChars(int value) =>
      value.clamp(lineCharsRange.min, lineCharsRange.max);

  static double normalizeInfoFontSize(double? value) {
    if (value == null || !value.isFinite) return kReaderInfoFontSize;
    return value.roundToDouble().clamp(minInfoFontSize, maxInfoFontSize);
  }
}
