import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/fonts/app_font.dart';
import 'package:night_reader/core/fonts/font_library.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/features/reader_v2/features/brightness/reader_v2_brightness.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_highlight_style.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_info_item.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_orientation.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_page_turn_speed.dart';
import 'package:night_reader/features/reader_v2/hybrid/layout/reader_paragraph_layout.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_prefs_repository.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_constants.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReaderV2SettingsController extends ChangeNotifier {
  /// 建構時就從已預載的 SharedPreferences 同步讀出使用者的設定：閱讀器第一幀
  /// 就照這些設定畫出正文與頁首頁尾的骨架，不必先等一次非同步載入。讀不出來
  /// （例如還原進來的值型別不對）就用預設值，閱讀器照樣打開。
  ReaderV2SettingsController({
    this._prefsRepository = const ReaderV2PrefsRepository(),
  }) {
    try {
      final prefs = getIt<SharedPreferences>();
      _prefsRepository.migrate(prefs);
      _persisted = _prefsRepository.read(prefs);
    } catch (error, stackTrace) {
      AppLog.e('閱讀設定讀取失敗: $error', error: error, stackTrace: stackTrace);
      _persisted = ReaderV2PrefsSnapshot.defaults();
    }
    _initFromCache(_persisted);
    _fonts.changes.addListener(_onFontsChanged);
    // 另一台選了這台還沒下載的字型：開書時在背景下載，好了再換上。
    unawaited(_fonts.ensure(readerFont));
  }

  FontLibrary get _fonts => FontLibrary.instance;

  /// 字型下載好、註冊了：正文照新的字族重排。
  void _onFontsChanged() {
    if (!_disposed) notifyListeners();
  }

  /// 正文目前用的字族；選的字型還不能用時是 null（系統字型）。
  String? get readerFontFamily => _fonts.familyOf(readerFont);

  static const double minReadableLineHeight =
      ReaderV2Style.minReadableLineHeight;
  static const double maxReadableLineHeight =
      ReaderV2Style.maxReadableLineHeight;
  static const double minAutoPageSpeed =
      ReaderV2PrefsRepository.minAutoPageSpeed;
  static const double maxAutoPageSpeed =
      ReaderV2PrefsRepository.maxAutoPageSpeed;
  static const double minPagePadding = ReaderV2PrefsRepository.minPagePadding;
  static const double maxPagePadding = ReaderV2PrefsRepository.maxPagePadding;
  static const double minChapterSpacing =
      ReaderV2PrefsRepository.minChapterSpacing;
  static const double maxChapterSpacing =
      ReaderV2PrefsRepository.maxChapterSpacing;
  static const double minTitleSpacing = ReaderV2PrefsRepository.minTitleSpacing;
  static const double maxTitleSpacing = ReaderV2PrefsRepository.maxTitleSpacing;

  final ReaderV2PrefsRepository _prefsRepository;

  double fontSize = ReaderV2PrefsSnapshot.defaults().fontSize;
  double titleFontSize = ReaderV2PrefsSnapshot.defaults().titleFontSize;
  double lineHeight = ReaderV2PrefsSnapshot.defaults().lineHeight;
  double paragraphSpacing = ReaderV2PrefsSnapshot.defaults().paragraphSpacing;
  double chapterSpacing = ReaderV2PrefsSnapshot.defaults().chapterSpacing;
  double letterSpacing = ReaderV2PrefsSnapshot.defaults().letterSpacing;
  int textIndent = ReaderV2PrefsSnapshot.defaults().textIndent;

  /// 正文兩側最少留白；實際的左右邊距照 [lineChars] 算（[paddingHorizontalFor]）。
  double paddingHorizontal = ReaderV2PrefsSnapshot.defaults().paddingHorizontal;
  int lineChars = ReaderV2PrefsSnapshot.defaults().lineChars;
  bool justifyText = ReaderV2PrefsSnapshot.defaults().justifyText;
  double paddingTop = ReaderV2PrefsSnapshot.defaults().paddingTop;
  double paddingBottom = ReaderV2PrefsSnapshot.defaults().paddingBottom;
  double footerOffset = ReaderV2PrefsSnapshot.defaults().footerOffset;
  bool hideStatusBar = ReaderV2PrefsSnapshot.defaults().hideStatusBar;
  ReaderV2InfoSlots headerInfo = ReaderV2PrefsSnapshot.defaults().headerInfo;
  ReaderV2InfoSlots footerInfo = ReaderV2PrefsSnapshot.defaults().footerInfo;
  int chineseConvert = ReaderV2PrefsSnapshot.defaults().chineseConvert;
  double autoPageSpeed = ReaderV2PrefsSnapshot.defaults().autoPageSpeed;
  bool showAddToShelfAlert =
      ReaderV2PrefsSnapshot.defaults().showAddToShelfAlert;
  List<int> clickActions = ReaderV2PrefsSnapshot.defaults().clickActions;
  ReaderV2HighlightColor highlightColor =
      ReaderV2PrefsSnapshot.defaults().highlightColor;
  double highlightStrength = ReaderV2PrefsSnapshot.defaults().highlightStrength;
  bool brightnessAuto = ReaderV2PrefsSnapshot.defaults().brightnessAuto;
  double brightness = ReaderV2PrefsSnapshot.defaults().brightness;
  bool volumeKeyPage = ReaderV2PrefsSnapshot.defaults().volumeKeyPage;
  bool volumeKeyReversed = ReaderV2PrefsSnapshot.defaults().volumeKeyReversed;
  double titleSpacing = ReaderV2PrefsSnapshot.defaults().titleSpacing;
  bool keepScreenOn = ReaderV2PrefsSnapshot.defaults().keepScreenOn;
  ReaderV2Orientation orientation =
      ReaderV2PrefsSnapshot.defaults().orientation;
  bool hideNavigationBar = ReaderV2PrefsSnapshot.defaults().hideNavigationBar;
  int pageTurnOverlap = ReaderV2PrefsSnapshot.defaults().pageTurnOverlap;
  ReaderV2PageTurnSpeed pageTurnSpeed =
      ReaderV2PrefsSnapshot.defaults().pageTurnSpeed;
  bool use24HourClock = ReaderV2PrefsSnapshot.defaults().use24HourClock;
  int progressFractionDigits =
      ReaderV2PrefsSnapshot.defaults().progressFractionDigits;
  double maxDim = ReaderV2PrefsSnapshot.defaults().maxDim;
  double edgeFade = ReaderV2PrefsSnapshot.defaults().edgeFade;
  bool ttsFollow = ReaderV2PrefsSnapshot.defaults().ttsFollow;
  bool bodyBold = ReaderV2PrefsSnapshot.defaults().bodyBold;
  bool titleBold = ReaderV2PrefsSnapshot.defaults().titleBold;
  bool titleCenter = ReaderV2PrefsSnapshot.defaults().titleCenter;
  double infoFontSize = ReaderV2PrefsSnapshot.defaults().infoFontSize;
  AppFont readerFont = ReaderV2PrefsSnapshot.defaults().readerFont;
  int _contentSettingsGeneration = 0;

  /// 最後一次確定落地（載入或保存成功）的設定；保存失敗時據此還原。
  late ReaderV2PrefsSnapshot _persisted;
  final Map<String, int> _saveGenerations = <String, int>{};
  final StreamController<String> _saveFailures =
      StreamController<String>.broadcast();
  bool _disposed = false;

  /// 設定保存失敗（已還原為先前的值）時發出的提示訊息。
  Stream<String> get saveFailures => _saveFailures.stream;

  int get contentSettingsGeneration => _contentSettingsGeneration;
  bool get showReadTitleAddition => true;

  /// 重新讀一次設定，接上別處（例如「閱讀偏好」頁）寫入的改動。
  Future<void> loadSettings() async {
    try {
      final snapshot = await _prefsRepository.load();
      _persisted = snapshot;
      // 別處（例如「閱讀偏好」頁）改了繁簡轉換時，重新載入也必須讓正文重轉。
      if (snapshot.chineseConvert != chineseConvert) {
        _contentSettingsGeneration += 1;
      }
      _initFromCache(snapshot);
      ChineseDisplay.mode.value = chineseConvert;
    } catch (error, stackTrace) {
      // 讀不到就沿用目前的值。
      AppLog.e('閱讀設定載入失敗: $error', error: error, stackTrace: stackTrace);
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  void _initFromCache(ReaderV2PrefsSnapshot snapshot) {
    fontSize = snapshot.fontSize;
    titleFontSize = snapshot.titleFontSize;
    lineHeight = ReaderV2Style.normalizeLineHeight(snapshot.lineHeight);
    paragraphSpacing = snapshot.paragraphSpacing;
    chapterSpacing = snapshot.chapterSpacing;
    letterSpacing = snapshot.letterSpacing;
    textIndent = snapshot.textIndent;
    autoPageSpeed = _normalizeAutoPageSpeed(snapshot.autoPageSpeed);
    chineseConvert = snapshot.chineseConvert;
    showAddToShelfAlert = snapshot.showAddToShelfAlert;
    clickActions = List<int>.from(snapshot.clickActions);
    paddingHorizontal = snapshot.paddingHorizontal;
    lineChars = snapshot.lineChars;
    justifyText = snapshot.justifyText;
    paddingTop = snapshot.paddingTop;
    paddingBottom = snapshot.paddingBottom;
    footerOffset = snapshot.footerOffset;
    hideStatusBar = snapshot.hideStatusBar;
    headerInfo = snapshot.headerInfo;
    footerInfo = snapshot.footerInfo;
    highlightColor = snapshot.highlightColor;
    highlightStrength = snapshot.highlightStrength;
    brightnessAuto = snapshot.brightnessAuto;
    brightness = snapshot.brightness;
    volumeKeyPage = snapshot.volumeKeyPage;
    volumeKeyReversed = snapshot.volumeKeyReversed;
    titleSpacing = snapshot.titleSpacing;
    keepScreenOn = snapshot.keepScreenOn;
    orientation = snapshot.orientation;
    hideNavigationBar = snapshot.hideNavigationBar;
    pageTurnOverlap = snapshot.pageTurnOverlap;
    pageTurnSpeed = snapshot.pageTurnSpeed;
    use24HourClock = snapshot.use24HourClock;
    progressFractionDigits = snapshot.progressFractionDigits;
    maxDim = snapshot.maxDim;
    edgeFade = snapshot.edgeFade;
    ttsFollow = snapshot.ttsFollow;
    bodyBold = snapshot.bodyBold;
    titleBold = snapshot.titleBold;
    titleCenter = snapshot.titleCenter;
    infoFontSize = snapshot.infoFontSize;
    readerFont = snapshot.readerFont;
  }

  @override
  void dispose() {
    _disposed = true;
    _fonts.changes.removeListener(_onFontsChanged);
    unawaited(_saveFailures.close());
    super.dispose();
  }

  /// 寫入偏好設定。記憶體中的值先行更新讓畫面即時反應；寫入失敗時，
  /// 以最後一次成功落地的值還原並通知，避免畫面顯示一個重開後就消失的設定。
  ///
  /// [field] 區分各設定的寫入序號：連續調整時只有該設定最新一次寫入的
  /// 失敗會觸發還原，較早的失敗不得把較新的值蓋回去。
  void _persist(
    String field,
    Future<void> Function() write, {
    required ReaderV2PrefsSnapshot Function(ReaderV2PrefsSnapshot persisted)
    onSaved,
    required void Function(ReaderV2PrefsSnapshot persisted) restore,
  }) {
    final generation = (_saveGenerations[field] ?? 0) + 1;
    _saveGenerations[field] = generation;
    unawaited(
      Future<void>.sync(write).then(
        (_) => _persisted = onSaved(_persisted),
        onError: (Object error, StackTrace stack) {
          AppLog.e(
            'Reader settings: save $field failed: $error',
            error: error,
            stackTrace: stack,
          );
          if (_disposed || _saveGenerations[field] != generation) return;
          restore(_persisted);
          notifyListeners();
          _saveFailures.add('設定儲存失敗，已恢復原本的值');
        },
      ),
    );
  }

  /// 存一個單純設定；寫入失敗時還原成最後落地的值（經 [restoreAs] 修正）。
  void _save<T>(
    ReaderV2Setting<T> setting,
    T value, {
    required void Function(T value) put,
    T Function(T persisted)? restoreAs,
  }) {
    _persist(
      setting.key,
      () => _prefsRepository.save(setting, value),
      onSaved: (persisted) => persisted.withValue(setting, value),
      restore: (persisted) {
        final restored = persisted.valueOf(setting);
        put(restoreAs == null ? restored : restoreAs(restored));
      },
    );
  }

  /// 改一個單純設定：與目前值相同就不動（[force] 時照寫）；否則更新欄位、
  /// 存檔並通知。[same] 決定「相同」的判斷，預設用 `==`。
  void _set<T>(
    ReaderV2Setting<T> setting,
    T value, {
    required T current,
    required void Function(T value) put,
    bool force = false,
    bool Function(T current, T value)? same,
    T Function(T persisted)? restoreAs,
  }) {
    final unchanged = same == null ? current == value : same(current, value);
    if (unchanged && !force) return;
    put(value);
    _save(setting, value, put: put, restoreAs: restoreAs);
    notifyListeners();
  }

  /// 排版的一項：有變才更新欄位，存檔每次都做（排版那幾項每次都寫）。回傳欄位有沒有變。
  bool _typography<T>(
    ReaderV2Setting<T> setting,
    T current,
    T value,
    void Function(T value) put, {
    T Function(T persisted)? restoreAs,
  }) {
    final changed = current != value;
    if (changed) put(value);
    _save(setting, value, put: put, restoreAs: restoreAs);
    return changed;
  }

  static bool _nearlyEqual(double current, double value) =>
      (current - value).abs() < 0.001;

  /// 正文一個字格的寬度（含字距與正文粗細）；量不到時是 null。
  double? get cellWidth => const ReaderParagraphLayout().measureCellWidth(
    fontSize: fontSize,
    letterSpacing: letterSpacing,
    bold: bodyBold,
    fontFamilyFallback: readerV2FontFallback(readerFontFamily),
  );

  /// 畫面寬 [viewportWidth] 時一行最多放得下幾個字（兩側留最少留白）。
  int lineCapacityFor(double viewportWidth) {
    final cell = cellWidth;
    if (cell == null) return 0;
    return ReaderV2TextLayoutFrame.lineCapacity(
      viewportWidth: viewportWidth,
      minPadding: paddingHorizontal,
      cellWidth: cell,
    );
  }

  /// 畫面寬 [viewportWidth] 時正文的左右邊距，頁首頁尾的左右內距也用它：
  /// 照每行字數把正文欄收窄置中，放不下就撐滿、只留最少留白。
  double paddingHorizontalFor(double viewportWidth) =>
      ReaderV2TextLayoutFrame.sidePadding(
        viewportWidth: viewportWidth,
        minPadding: paddingHorizontal,
        cellWidth: cellWidth,
        lineChars: lineChars,
      );

  /// 閱讀選單與面板最窄的寬度：下方選單的一排圓鈕與面板的步進列在這個
  /// 寬度都放得下（一般手機的寬度）。
  static const double menuMinWidth = 360;

  /// 閱讀選單與面板左右對齊的位置（畫面寬 [viewportWidth]）：正文欄照
  /// 每行字數收窄時，上下選單與面板的左右緣對齊正文的左右邊，但不窄過
  /// [menuMinWidth]；沒收窄（手機直拿）時是 null，上下選單的位置照
  /// [menuInsetFor]、面板照預設寬度。
  double? menuSideFor(double viewportWidth) {
    final side = math.min(
      paddingHorizontalFor(viewportWidth),
      (viewportWidth - menuMinWidth) / 2,
    );
    return side > paddingHorizontal ? side : null;
  }

  /// 沒收窄時上下選單比正文的左右邊再往外推多少：膠囊兩端連圓角一起蓋住
  /// 每一行的頭尾（使用者 2026-11-05 從「對齊正文」「外推 4」選定）。
  static const double menuTextOverhang = 4;

  /// 上下選單離畫面左右邊最少多遠：正文貼著畫面邊時，選單也不貼死。
  static const double menuMinInset = 4;

  /// 上下選單離畫面左右邊多遠（畫面寬 [viewportWidth]）：正文欄
  /// 收窄時是 [menuSideFor]；沒收窄時比正文的左右邊再往外
  /// [menuTextOverhang]，正文留白夠寬時照原本離邊 16，最少 [menuMinInset]。
  double menuInsetFor(double viewportWidth) =>
      menuSideFor(viewportWidth) ??
      (paddingHorizontalFor(viewportWidth) - menuTextOverhang)
          .clamp(menuMinInset, AppGrouped.margin)
          .toDouble();

  ReaderV2Style readStyleFor(
    EdgeInsets mediaPadding, {
    required double viewportWidth,
    bool topInfoReservedExternally = false,
    bool bottomInfoReservedExternally = false,
  }) {
    final horizontal = paddingHorizontalFor(viewportWidth);
    final top =
        (topInfoReservedExternally
            ? 0.0
            : mediaPadding.top * kReaderContentTopSafeAreaFactor) +
        kReaderContentTopSpacing;
    final bottom = bottomInfoReservedExternally ? 0.0 : mediaPadding.bottom;
    return ReaderV2Style(
      fontSize: fontSize,
      lineHeight: ReaderV2Style.normalizeLineHeight(lineHeight),
      letterSpacing: letterSpacing,
      paragraphSpacing: paragraphSpacing,
      chapterSpacing: chapterSpacing,
      paddingTop: top,
      paddingBottom: bottom,
      paddingLeft: horizontal,
      paddingRight: horizontal,
      justify: justifyText,
      bold: bodyBold,
      titleBold: titleBold,
      titleCenter: titleCenter,
      fontFamily: readerFontFamily,
      textIndent: textIndent,
      titleFontSize: titleFontSize,
      titleSpacing: titleSpacing,
    );
  }

  void setFontSize(double value) => setTypography(fontSize: value);
  void setLineHeight(double value) => setTypography(lineHeight: value);
  void setParagraphSpacing(double value) =>
      setTypography(paragraphSpacing: value);
  void setLetterSpacing(double value) => setTypography(letterSpacing: value);

  void setTypography({
    double? fontSize,
    double? titleFontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? chapterSpacing,
    double? titleSpacing,
    double? letterSpacing,
    int? textIndent,
  }) {
    var changed = false;
    if (titleSpacing != null) {
      changed |= _typography(
        ReaderV2Settings.titleSpacing,
        this.titleSpacing,
        titleSpacing,
        (value) => this.titleSpacing = value,
      );
    }
    if (textIndent != null) {
      changed |= _typography(
        ReaderV2Settings.textIndent,
        this.textIndent,
        textIndent,
        (value) => this.textIndent = value,
      );
    }
    if (fontSize != null) {
      changed |= _typography(
        ReaderV2Settings.fontSize,
        this.fontSize,
        fontSize,
        (value) => this.fontSize = value,
      );
    }
    if (titleFontSize != null) {
      changed |= _typography(
        ReaderV2Settings.titleFontSize,
        this.titleFontSize,
        titleFontSize,
        (value) => this.titleFontSize = value,
      );
    }
    if (lineHeight != null) {
      changed |= _typography(
        ReaderV2Settings.lineHeight,
        this.lineHeight,
        ReaderV2Style.normalizeLineHeight(lineHeight),
        (value) => this.lineHeight = value,
        restoreAs: ReaderV2Style.normalizeLineHeight,
      );
    }
    if (paragraphSpacing != null) {
      changed |= _typography(
        ReaderV2Settings.paragraphSpacing,
        this.paragraphSpacing,
        paragraphSpacing,
        (value) => this.paragraphSpacing = value,
      );
    }
    if (chapterSpacing != null) {
      changed |= _typography(
        ReaderV2Settings.chapterSpacing,
        this.chapterSpacing,
        chapterSpacing,
        (value) => this.chapterSpacing = value,
      );
    }
    if (letterSpacing != null) {
      changed |= _typography(
        ReaderV2Settings.letterSpacing,
        this.letterSpacing,
        letterSpacing,
        (value) => this.letterSpacing = value,
      );
    }
    if (changed) notifyListeners();
  }

  /// 將字號、標題、行高、字距、段距、章節間距、首行縮排、粗細、標題對齊與
  /// 正文字型
  /// 恢復為預設值。
  void resetTypography() {
    final defaults = ReaderV2PrefsSnapshot.defaults();
    setBodyBold(defaults.bodyBold, force: true);
    setTitleBold(defaults.titleBold, force: true);
    setTitleCenter(defaults.titleCenter, force: true);
    setReaderFont(defaults.readerFont, force: true);
    setTypography(
      fontSize: defaults.fontSize,
      titleFontSize: defaults.titleFontSize,
      lineHeight: defaults.lineHeight,
      paragraphSpacing: defaults.paragraphSpacing,
      chapterSpacing: defaults.chapterSpacing,
      titleSpacing: defaults.titleSpacing,
      letterSpacing: defaults.letterSpacing,
      textIndent: defaults.textIndent,
    );
  }

  /// 正文粗細、標題粗細、標題對齊與正文字型是否都是預設值。
  bool get isTypographyChoicesDefault {
    final defaults = ReaderV2PrefsSnapshot.defaults();
    return bodyBold == defaults.bodyBold &&
        titleBold == defaults.titleBold &&
        titleCenter == defaults.titleCenter &&
        readerFont == defaults.readerFont;
  }

  void setBodyBold(bool value, {bool force = false}) => _set(
    ReaderV2Settings.bodyBold,
    value,
    current: bodyBold,
    put: (v) => bodyBold = v,
    force: force,
  );

  void setTitleBold(bool value, {bool force = false}) => _set(
    ReaderV2Settings.titleBold,
    value,
    current: titleBold,
    put: (v) => titleBold = v,
    force: force,
  );

  void setTitleCenter(bool value, {bool force = false}) => _set(
    ReaderV2Settings.titleCenter,
    value,
    current: titleCenter,
    put: (v) => titleCenter = v,
    force: force,
  );

  /// 正文字型；選了還沒下載的就開始下載，好了才換上（[_onFontsChanged]）。
  void setReaderFont(AppFont value, {bool force = false}) {
    if (readerFont == value && !force) return;
    readerFont = value;
    _save(ReaderV2Settings.readerFont, value, put: (v) => readerFont = v);
    unawaited(_fonts.ensure(value));
    notifyListeners();
  }

  /// 頁首頁尾資訊的字級；那一列跟著變高，正文區跟著讓出位置。
  void setInfoFontSize(double value, {bool force = false}) {
    final normalized = ReaderV2PrefsRepository.normalizeInfoFontSize(value);
    _set(
      ReaderV2Settings.infoFontSize,
      normalized,
      current: infoFontSize,
      put: (v) => infoFontSize = v,
      force: force,
    );
  }

  void setAutoPageSpeed(double value) {
    final normalized = _normalizeAutoPageSpeed(value);
    _set(
      ReaderV2Settings.autoPageSpeed,
      normalized,
      current: autoPageSpeed,
      put: (v) => autoPageSpeed = v,
      same: _nearlyEqual,
      restoreAs: _normalizeAutoPageSpeed,
    );
  }

  void setHighlightColor(ReaderV2HighlightColor value) => _set(
    ReaderV2Settings.highlightColor,
    value,
    current: highlightColor,
    put: (v) => highlightColor = v,
  );

  void setHighlightStrength(double value) {
    final normalized = ReaderV2HighlightStrength.normalize(value);
    _set(
      ReaderV2Settings.highlightStrength,
      normalized,
      current: highlightStrength,
      put: (v) => highlightStrength = v,
      same: _nearlyEqual,
    );
  }

  /// 亮度改回跟隨系統，或改用自己的亮度（沿用上次調的位置）。
  void setBrightnessAuto(bool value) => _set(
    ReaderV2Settings.brightnessAuto,
    value,
    current: brightnessAuto,
    put: (v) => brightnessAuto = v,
  );

  /// 拖動亮度條：改用自己的亮度並立刻套用。拖動中 [persist] 為 false，
  /// 放開時再寫入一次，不在每一格都寫偏好設定。
  void setBrightness(double value, {bool persist = true}) {
    final normalized = ReaderV2Brightness.normalize(value);
    final changed = brightness != normalized || brightnessAuto;
    brightness = normalized;
    if (brightnessAuto) setBrightnessAuto(false);
    if (persist) {
      _save(
        ReaderV2Settings.brightness,
        normalized,
        put: (v) => brightness = v,
      );
    }
    if (changed) notifyListeners();
  }

  void setVolumeKeyPage(bool value) => _set(
    ReaderV2Settings.volumeKeyPage,
    value,
    current: volumeKeyPage,
    put: (v) => volumeKeyPage = v,
  );

  void setVolumeKeyReversed(bool value) => _set(
    ReaderV2Settings.volumeKeyReversed,
    value,
    current: volumeKeyReversed,
    put: (v) => volumeKeyReversed = v,
  );

  void setKeepScreenOn(bool value) => _set(
    ReaderV2Settings.keepScreenOn,
    value,
    current: keepScreenOn,
    put: (v) => keepScreenOn = v,
  );

  void setOrientation(ReaderV2Orientation value) => _set(
    ReaderV2Settings.orientation,
    value,
    current: orientation,
    put: (v) => orientation = v,
  );

  void setHideNavigationBar(bool value, {bool force = false}) => _set(
    ReaderV2Settings.hideNavigationBar,
    value,
    current: hideNavigationBar,
    put: (v) => hideNavigationBar = v,
    force: force,
  );

  void setPageTurnOverlap(int value) {
    final normalized = ReaderV2PrefsRepository.normalizePageTurnOverlap(value);
    _set(
      ReaderV2Settings.pageTurnOverlap,
      normalized,
      current: pageTurnOverlap,
      put: (v) => pageTurnOverlap = v,
    );
  }

  void setPageTurnSpeed(ReaderV2PageTurnSpeed value) => _set(
    ReaderV2Settings.pageTurnSpeed,
    value,
    current: pageTurnSpeed,
    put: (v) => pageTurnSpeed = v,
  );

  void setUse24HourClock(bool value, {bool force = false}) => _set(
    ReaderV2Settings.use24HourClock,
    value,
    current: use24HourClock,
    put: (v) => use24HourClock = v,
    force: force,
  );

  void setProgressFractionDigits(int value, {bool force = false}) {
    final normalized = ReaderV2PrefsRepository.normalizeProgressFractionDigits(
      value,
    );
    _set(
      ReaderV2Settings.progressFractionDigits,
      normalized,
      current: progressFractionDigits,
      put: (v) => progressFractionDigits = v,
      force: force,
    );
  }

  void setMaxDim(double value) {
    final normalized = ReaderV2Brightness.normalizeMaxDim(value);
    _set(
      ReaderV2Settings.maxDim,
      normalized,
      current: maxDim,
      put: (v) => maxDim = v,
    );
  }

  void setEdgeFade(double value, {bool force = false}) {
    final normalized = ReaderV2PrefsRepository.normalizeEdgeFade(value);
    _set(
      ReaderV2Settings.edgeFade,
      normalized,
      current: edgeFade,
      put: (v) => edgeFade = v,
      force: force,
    );
  }

  void setTtsFollow(bool value) => _set(
    ReaderV2Settings.ttsFollow,
    value,
    current: ttsFollow,
    put: (v) => ttsFollow = v,
  );

  /// 繁簡轉換：換了才讓正文重轉（[_contentSettingsGeneration]）並更新顯示模式。
  void setChineseConvert(int value) => _set(
    ReaderV2Settings.chineseConvert,
    value,
    current: chineseConvert,
    put: _putChineseConvert,
  );

  void _putChineseConvert(int value) {
    if (chineseConvert == value) return;
    chineseConvert = value;
    _contentSettingsGeneration += 1;
    ChineseDisplay.mode.value = value;
  }

  void setClickAction(int zone, int action) {
    if (zone < 0 || zone >= clickActions.length) return;
    _setClickActions(List<int>.from(clickActions)..[zone] = action);
  }

  void resetClickActions() {
    _setClickActions(ReaderV2PrefsSnapshot.defaults().clickActions);
  }

  void _setClickActions(List<int> next) {
    clickActions = next;
    _save(
      ReaderV2Settings.clickActions,
      next,
      put: (v) => clickActions = v,
      restoreAs: (v) => List<int>.from(v),
    );
    notifyListeners();
  }

  void setPagePadding({
    double? horizontal,
    double? top,
    double? bottom,
    bool force = false,
  }) {
    var changed = false;
    if (horizontal != null) {
      final value = _normalizePagePadding(horizontal);
      if (force || paddingHorizontal != value) {
        paddingHorizontal = value;
        changed = true;
        _save(
          ReaderV2Settings.paddingHorizontal,
          value,
          put: (v) => paddingHorizontal = v,
        );
      }
    }
    if (top != null) {
      final value = _normalizePagePadding(top);
      if (force || paddingTop != value) {
        paddingTop = value;
        changed = true;
        _save(ReaderV2Settings.paddingTop, value, put: (v) => paddingTop = v);
      }
    }
    if (bottom != null) {
      final value = _normalizePagePadding(bottom);
      if (force || paddingBottom != value) {
        paddingBottom = value;
        changed = true;
        _save(
          ReaderV2Settings.paddingBottom,
          value,
          put: (v) => paddingBottom = v,
        );
      }
    }
    if (changed) notifyListeners();
  }

  void setLineChars(int value, {bool force = false}) {
    final normalized = ReaderV2PrefsRepository.normalizeLineChars(value);
    _set(
      ReaderV2Settings.lineChars,
      normalized,
      current: lineChars,
      put: (v) => lineChars = v,
      force: force,
    );
  }

  /// 頁尾資訊列底部到畫面底部的距離。
  void setFooterOffset(double value, {bool force = false}) {
    final normalized = _normalizePagePadding(value);
    _set(
      ReaderV2Settings.footerOffset,
      normalized,
      current: footerOffset,
      put: (v) => footerOffset = v,
      force: force,
    );
  }

  void setJustifyText(bool value, {bool force = false}) => _set(
    ReaderV2Settings.justifyText,
    value,
    current: justifyText,
    put: (v) => justifyText = v,
    force: force,
  );

  /// 恢復預設一律把預設值寫入（`force`），不看記憶體裡的值：畫面開著時另一台
  /// 的設定同步進來，記憶體裡還是舊值，看起來已是預設就不寫，另一台的值會
  /// 留著。排版那幾項（[setTypography]）本來就每次都寫。
  ///
  /// 將每行字數、邊距、左右對齊、上下緣漸隱、頁尾位置、系統列與頁首／頁尾（含時間
  /// 與進度的格式）恢復為預設值。
  void resetPageLayout() {
    final defaults = ReaderV2PrefsSnapshot.defaults();
    setPagePadding(
      horizontal: defaults.paddingHorizontal,
      top: defaults.paddingTop,
      bottom: defaults.paddingBottom,
      force: true,
    );
    setLineChars(defaults.lineChars, force: true);
    setJustifyText(defaults.justifyText, force: true);
    setEdgeFade(defaults.edgeFade, force: true);
    setFooterOffset(defaults.footerOffset, force: true);
    setHideStatusBar(defaults.hideStatusBar, force: true);
    setHideNavigationBar(defaults.hideNavigationBar, force: true);
    setHeaderInfo(defaults.headerInfo, force: true);
    setFooterInfo(defaults.footerInfo, force: true);
    setUse24HourClock(defaults.use24HourClock, force: true);
    setProgressFractionDigits(defaults.progressFractionDigits, force: true);
    setInfoFontSize(defaults.infoFontSize, force: true);
  }

  bool get isPageLayoutDefault {
    final defaults = ReaderV2PrefsSnapshot.defaults();
    return paddingHorizontal == defaults.paddingHorizontal &&
        lineChars == defaults.lineChars &&
        justifyText == defaults.justifyText &&
        paddingTop == defaults.paddingTop &&
        paddingBottom == defaults.paddingBottom &&
        edgeFade == defaults.edgeFade &&
        footerOffset == defaults.footerOffset &&
        hideStatusBar == defaults.hideStatusBar &&
        hideNavigationBar == defaults.hideNavigationBar &&
        headerInfo == defaults.headerInfo &&
        footerInfo == defaults.footerInfo &&
        use24HourClock == defaults.use24HourClock &&
        progressFractionDigits == defaults.progressFractionDigits &&
        infoFontSize == defaults.infoFontSize;
  }

  void setHideStatusBar(bool value, {bool force = false}) => _set(
    ReaderV2Settings.hideStatusBar,
    value,
    current: hideStatusBar,
    put: (v) => hideStatusBar = v,
    force: force,
  );

  void setHeaderInfo(ReaderV2InfoSlots value, {bool force = false}) => _set(
    ReaderV2Settings.headerInfo,
    value,
    current: headerInfo,
    put: (v) => headerInfo = v,
    force: force,
  );

  void setFooterInfo(ReaderV2InfoSlots value, {bool force = false}) => _set(
    ReaderV2Settings.footerInfo,
    value,
    current: footerInfo,
    put: (v) => footerInfo = v,
    force: force,
  );

  double _normalizePagePadding(double value) {
    if (!value.isFinite) return 0.0;
    return value.clamp(minPagePadding, maxPagePadding).toDouble();
  }

  double _normalizeAutoPageSpeed(double value) {
    if (!value.isFinite) return ReaderV2PrefsSnapshot.defaults().autoPageSpeed;
    return value.clamp(minAutoPageSpeed, maxAutoPageSpeed).toDouble();
  }
}
