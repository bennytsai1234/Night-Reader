import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/features/reader_v2/features/brightness/reader_v2_brightness.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_highlight_style.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_info_item.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_orientation.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_page_turn_speed.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_prefs_repository.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_constants.dart';
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
  }

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

  double fontSize = 18.0;
  double titleFontSize = 18.0 + kReaderV2DefaultTitleSizeDelta;
  double lineHeight = ReaderV2PrefsSnapshot.defaults().lineHeight;
  double paragraphSpacing = ReaderV2PrefsSnapshot.defaults().paragraphSpacing;
  double chapterSpacing = ReaderV2PrefsSnapshot.defaults().chapterSpacing;
  double letterSpacing = ReaderV2PrefsSnapshot.defaults().letterSpacing;
  int textIndent = 2;
  double paddingHorizontal = ReaderV2PrefsSnapshot.defaults().paddingHorizontal;
  bool justifyText = ReaderV2PrefsSnapshot.defaults().justifyText;
  double paddingTop = ReaderV2PrefsSnapshot.defaults().paddingTop;
  double paddingBottom = ReaderV2PrefsSnapshot.defaults().paddingBottom;
  double footerOffset = ReaderV2PrefsSnapshot.defaults().footerOffset;
  bool hideStatusBar = false;
  ReaderV2InfoSlots headerInfo = ReaderV2PrefsSnapshot.defaults().headerInfo;
  ReaderV2InfoSlots footerInfo = ReaderV2PrefsSnapshot.defaults().footerInfo;
  int chineseConvert = 0;
  double autoPageSpeed = ReaderV2PrefsSnapshot.defaults().autoPageSpeed;
  bool showAddToShelfAlert = true;
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
  }

  @override
  void dispose() {
    _disposed = true;
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

  ReaderV2Style readStyleFor(
    EdgeInsets mediaPadding, {
    bool topInfoReservedExternally = false,
    bool bottomInfoReservedExternally = false,
  }) {
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
      paddingLeft: paddingHorizontal,
      paddingRight: paddingHorizontal,
      justify: justifyText,
      bold: false,
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
      if (this.titleSpacing != titleSpacing) {
        this.titleSpacing = titleSpacing;
        changed = true;
      }
      _persist(
        'titleSpacing',
        () => _prefsRepository.saveTitleSpacing(titleSpacing),
        onSaved: (p) => p.copyWith(titleSpacing: titleSpacing),
        restore: (p) => this.titleSpacing = p.titleSpacing,
      );
    }
    if (textIndent != null) {
      if (this.textIndent != textIndent) {
        this.textIndent = textIndent;
        changed = true;
      }
      _persist(
        'textIndent',
        () => _prefsRepository.saveTextIndent(textIndent),
        onSaved: (p) => p.copyWith(textIndent: textIndent),
        restore: (p) => this.textIndent = p.textIndent,
      );
    }
    if (fontSize != null) {
      if (this.fontSize != fontSize) {
        this.fontSize = fontSize;
        changed = true;
      }
      _persist(
        'fontSize',
        () => _prefsRepository.saveFontSize(fontSize),
        onSaved: (p) => p.copyWith(fontSize: fontSize),
        restore: (p) => this.fontSize = p.fontSize,
      );
    }
    if (titleFontSize != null) {
      if (this.titleFontSize != titleFontSize) {
        this.titleFontSize = titleFontSize;
        changed = true;
      }
      _persist(
        'titleFontSize',
        () => _prefsRepository.saveTitleFontSize(titleFontSize),
        onSaved: (p) => p.copyWith(titleFontSize: titleFontSize),
        restore: (p) => this.titleFontSize = p.titleFontSize,
      );
    }
    if (lineHeight != null) {
      final normalized = ReaderV2Style.normalizeLineHeight(lineHeight);
      if (this.lineHeight != normalized) {
        this.lineHeight = normalized;
        changed = true;
      }
      _persist(
        'lineHeight',
        () => _prefsRepository.saveLineHeight(normalized),
        onSaved: (p) => p.copyWith(lineHeight: normalized),
        restore: (p) =>
            this.lineHeight = ReaderV2Style.normalizeLineHeight(p.lineHeight),
      );
    }
    if (paragraphSpacing != null) {
      if (this.paragraphSpacing != paragraphSpacing) {
        this.paragraphSpacing = paragraphSpacing;
        changed = true;
      }
      _persist(
        'paragraphSpacing',
        () => _prefsRepository.saveParagraphSpacing(paragraphSpacing),
        onSaved: (p) => p.copyWith(paragraphSpacing: paragraphSpacing),
        restore: (p) => this.paragraphSpacing = p.paragraphSpacing,
      );
    }
    if (chapterSpacing != null) {
      if (this.chapterSpacing != chapterSpacing) {
        this.chapterSpacing = chapterSpacing;
        changed = true;
      }
      _persist(
        'chapterSpacing',
        () => _prefsRepository.saveChapterSpacing(chapterSpacing),
        onSaved: (p) => p.copyWith(chapterSpacing: chapterSpacing),
        restore: (p) => this.chapterSpacing = p.chapterSpacing,
      );
    }
    if (letterSpacing != null) {
      if (this.letterSpacing != letterSpacing) {
        this.letterSpacing = letterSpacing;
        changed = true;
      }
      _persist(
        'letterSpacing',
        () => _prefsRepository.saveLetterSpacing(letterSpacing),
        onSaved: (p) => p.copyWith(letterSpacing: letterSpacing),
        restore: (p) => this.letterSpacing = p.letterSpacing,
      );
    }
    if (changed) notifyListeners();
  }

  /// 將字號、標題、行高、字距、段距、章節間距與首行縮排恢復為預設值。
  void resetTypography() {
    final defaults = ReaderV2PrefsSnapshot.defaults();
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

  void setAutoPageSpeed(double value) {
    final normalized = _normalizeAutoPageSpeed(value);
    if ((autoPageSpeed - normalized).abs() < 0.001) return;
    autoPageSpeed = normalized;
    _persist(
      'autoPageSpeed',
      () => _prefsRepository.saveAutoPageSpeed(normalized),
      onSaved: (p) => p.copyWith(autoPageSpeed: normalized),
      restore: (p) => autoPageSpeed = _normalizeAutoPageSpeed(p.autoPageSpeed),
    );
    notifyListeners();
  }

  void setHighlightColor(ReaderV2HighlightColor value) {
    if (highlightColor == value) return;
    highlightColor = value;
    _persist(
      'highlightColor',
      () => _prefsRepository.saveHighlightColor(value),
      onSaved: (p) => p.copyWith(highlightColor: value),
      restore: (p) => highlightColor = p.highlightColor,
    );
    notifyListeners();
  }

  void setHighlightStrength(double value) {
    final normalized = ReaderV2HighlightStrength.normalize(value);
    if ((highlightStrength - normalized).abs() < 0.001) return;
    highlightStrength = normalized;
    _persist(
      'highlightStrength',
      () => _prefsRepository.saveHighlightStrength(normalized),
      onSaved: (p) => p.copyWith(highlightStrength: normalized),
      restore: (p) => highlightStrength = p.highlightStrength,
    );
    notifyListeners();
  }

  /// 亮度改回跟隨系統，或改用自己的亮度（沿用上次調的位置）。
  void setBrightnessAuto(bool value) {
    if (brightnessAuto == value) return;
    brightnessAuto = value;
    _persist(
      'brightnessAuto',
      () => _prefsRepository.saveBrightnessAuto(value),
      onSaved: (p) => p.copyWith(brightnessAuto: value),
      restore: (p) => brightnessAuto = p.brightnessAuto,
    );
    notifyListeners();
  }

  /// 拖動亮度條：改用自己的亮度並立刻套用。拖動中 [persist] 為 false，
  /// 放開時再寫入一次，不在每一格都寫偏好設定。
  void setBrightness(double value, {bool persist = true}) {
    final normalized = ReaderV2Brightness.normalize(value);
    final changed = brightness != normalized || brightnessAuto;
    brightness = normalized;
    if (brightnessAuto) setBrightnessAuto(false);
    if (persist) {
      _persist(
        'brightness',
        () => _prefsRepository.saveBrightness(normalized),
        onSaved: (p) => p.copyWith(brightness: normalized),
        restore: (p) => brightness = p.brightness,
      );
    }
    if (changed) notifyListeners();
  }

  void setVolumeKeyPage(bool value) {
    if (volumeKeyPage == value) return;
    volumeKeyPage = value;
    _persist(
      'volumeKeyPage',
      () => _prefsRepository.saveVolumeKeyPage(value),
      onSaved: (p) => p.copyWith(volumeKeyPage: value),
      restore: (p) => volumeKeyPage = p.volumeKeyPage,
    );
    notifyListeners();
  }

  void setVolumeKeyReversed(bool value) {
    if (volumeKeyReversed == value) return;
    volumeKeyReversed = value;
    _persist(
      'volumeKeyReversed',
      () => _prefsRepository.saveVolumeKeyReversed(value),
      onSaved: (p) => p.copyWith(volumeKeyReversed: value),
      restore: (p) => volumeKeyReversed = p.volumeKeyReversed,
    );
    notifyListeners();
  }

  void setKeepScreenOn(bool value) {
    if (keepScreenOn == value) return;
    keepScreenOn = value;
    _persist(
      'keepScreenOn',
      () => _prefsRepository.saveKeepScreenOn(value),
      onSaved: (p) => p.copyWith(keepScreenOn: value),
      restore: (p) => keepScreenOn = p.keepScreenOn,
    );
    notifyListeners();
  }

  void setOrientation(ReaderV2Orientation value) {
    if (orientation == value) return;
    orientation = value;
    _persist(
      'orientation',
      () => _prefsRepository.saveOrientation(value),
      onSaved: (p) => p.copyWith(orientation: value),
      restore: (p) => orientation = p.orientation,
    );
    notifyListeners();
  }

  void setHideNavigationBar(bool value) {
    if (hideNavigationBar == value) return;
    hideNavigationBar = value;
    _persist(
      'hideNavigationBar',
      () => _prefsRepository.saveHideNavigationBar(value),
      onSaved: (p) => p.copyWith(hideNavigationBar: value),
      restore: (p) => hideNavigationBar = p.hideNavigationBar,
    );
    notifyListeners();
  }

  void setPageTurnOverlap(int value) {
    final normalized = ReaderV2PrefsRepository.normalizePageTurnOverlap(value);
    if (pageTurnOverlap == normalized) return;
    pageTurnOverlap = normalized;
    _persist(
      'pageTurnOverlap',
      () => _prefsRepository.savePageTurnOverlap(normalized),
      onSaved: (p) => p.copyWith(pageTurnOverlap: normalized),
      restore: (p) => pageTurnOverlap = p.pageTurnOverlap,
    );
    notifyListeners();
  }

  void setPageTurnSpeed(ReaderV2PageTurnSpeed value) {
    if (pageTurnSpeed == value) return;
    pageTurnSpeed = value;
    _persist(
      'pageTurnSpeed',
      () => _prefsRepository.savePageTurnSpeed(value),
      onSaved: (p) => p.copyWith(pageTurnSpeed: value),
      restore: (p) => pageTurnSpeed = p.pageTurnSpeed,
    );
    notifyListeners();
  }

  void setUse24HourClock(bool value) {
    if (use24HourClock == value) return;
    use24HourClock = value;
    _persist(
      'use24HourClock',
      () => _prefsRepository.saveUse24HourClock(value),
      onSaved: (p) => p.copyWith(use24HourClock: value),
      restore: (p) => use24HourClock = p.use24HourClock,
    );
    notifyListeners();
  }

  void setProgressFractionDigits(int value) {
    final normalized = ReaderV2PrefsRepository.normalizeProgressFractionDigits(
      value,
    );
    if (progressFractionDigits == normalized) return;
    progressFractionDigits = normalized;
    _persist(
      'progressFractionDigits',
      () => _prefsRepository.saveProgressFractionDigits(normalized),
      onSaved: (p) => p.copyWith(progressFractionDigits: normalized),
      restore: (p) => progressFractionDigits = p.progressFractionDigits,
    );
    notifyListeners();
  }

  void setMaxDim(double value) {
    final normalized = ReaderV2Brightness.normalizeMaxDim(value);
    if (maxDim == normalized) return;
    maxDim = normalized;
    _persist(
      'maxDim',
      () => _prefsRepository.saveMaxDim(normalized),
      onSaved: (p) => p.copyWith(maxDim: normalized),
      restore: (p) => maxDim = p.maxDim,
    );
    notifyListeners();
  }

  void setEdgeFade(double value) {
    final normalized = ReaderV2PrefsRepository.normalizeEdgeFade(value);
    if (edgeFade == normalized) return;
    edgeFade = normalized;
    _persist(
      'edgeFade',
      () => _prefsRepository.saveEdgeFade(normalized),
      onSaved: (p) => p.copyWith(edgeFade: normalized),
      restore: (p) => edgeFade = p.edgeFade,
    );
    notifyListeners();
  }

  void setTtsFollow(bool value) {
    if (ttsFollow == value) return;
    ttsFollow = value;
    _persist(
      'ttsFollow',
      () => _prefsRepository.saveTtsFollow(value),
      onSaved: (p) => p.copyWith(ttsFollow: value),
      restore: (p) => ttsFollow = p.ttsFollow,
    );
    notifyListeners();
  }

  void setChineseConvert(int value) {
    if (chineseConvert == value) return;
    chineseConvert = value;
    _contentSettingsGeneration += 1;
    ChineseDisplay.mode.value = value;
    _persist(
      'chineseConvert',
      () => _prefsRepository.saveChineseConvert(value),
      onSaved: (p) => p.copyWith(chineseConvert: value),
      restore: (p) {
        if (chineseConvert == p.chineseConvert) return;
        chineseConvert = p.chineseConvert;
        _contentSettingsGeneration += 1;
        ChineseDisplay.mode.value = p.chineseConvert;
      },
    );
    notifyListeners();
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
    _persist(
      'clickActions',
      () => _prefsRepository.saveClickActions(next),
      onSaved: (p) => p.copyWith(clickActions: next),
      restore: (p) => clickActions = List<int>.from(p.clickActions),
    );
    notifyListeners();
  }

  void setPagePadding({double? horizontal, double? top, double? bottom}) {
    var changed = false;
    if (horizontal != null) {
      final value = _normalizePagePadding(horizontal);
      if (paddingHorizontal != value) {
        paddingHorizontal = value;
        changed = true;
        _persist(
          'paddingHorizontal',
          () => _prefsRepository.savePaddingHorizontal(value),
          onSaved: (p) => p.copyWith(paddingHorizontal: value),
          restore: (p) => paddingHorizontal = p.paddingHorizontal,
        );
      }
    }
    if (top != null) {
      final value = _normalizePagePadding(top);
      if (paddingTop != value) {
        paddingTop = value;
        changed = true;
        _persist(
          'paddingTop',
          () => _prefsRepository.savePaddingTop(value),
          onSaved: (p) => p.copyWith(paddingTop: value),
          restore: (p) => paddingTop = p.paddingTop,
        );
      }
    }
    if (bottom != null) {
      final value = _normalizePagePadding(bottom);
      if (paddingBottom != value) {
        paddingBottom = value;
        changed = true;
        _persist(
          'paddingBottom',
          () => _prefsRepository.savePaddingBottom(value),
          onSaved: (p) => p.copyWith(paddingBottom: value),
          restore: (p) => paddingBottom = p.paddingBottom,
        );
      }
    }
    if (changed) notifyListeners();
  }

  /// 頁尾資訊列底部到畫面底部的距離。
  void setFooterOffset(double value) {
    final normalized = _normalizePagePadding(value);
    if (footerOffset == normalized) return;
    footerOffset = normalized;
    _persist(
      'footerOffset',
      () => _prefsRepository.saveFooterOffset(normalized),
      onSaved: (p) => p.copyWith(footerOffset: normalized),
      restore: (p) => footerOffset = p.footerOffset,
    );
    notifyListeners();
  }

  void setJustifyText(bool value) {
    if (justifyText == value) return;
    justifyText = value;
    _persist(
      'justifyText',
      () => _prefsRepository.saveJustifyText(value),
      onSaved: (p) => p.copyWith(justifyText: value),
      restore: (p) => justifyText = p.justifyText,
    );
    notifyListeners();
  }

  /// 將邊距、左右對齊、上下緣漸隱、頁尾位置、系統列與頁首／頁尾（含時間
  /// 與進度的格式）恢復為預設值。
  void resetPageLayout() {
    final defaults = ReaderV2PrefsSnapshot.defaults();
    setPagePadding(
      horizontal: defaults.paddingHorizontal,
      top: defaults.paddingTop,
      bottom: defaults.paddingBottom,
    );
    setJustifyText(defaults.justifyText);
    setEdgeFade(defaults.edgeFade);
    setFooterOffset(defaults.footerOffset);
    setHideStatusBar(defaults.hideStatusBar);
    setHideNavigationBar(defaults.hideNavigationBar);
    setHeaderInfo(defaults.headerInfo);
    setFooterInfo(defaults.footerInfo);
    setUse24HourClock(defaults.use24HourClock);
    setProgressFractionDigits(defaults.progressFractionDigits);
  }

  bool get isPageLayoutDefault {
    final defaults = ReaderV2PrefsSnapshot.defaults();
    return paddingHorizontal == defaults.paddingHorizontal &&
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
        progressFractionDigits == defaults.progressFractionDigits;
  }

  void setHideStatusBar(bool value) {
    if (hideStatusBar == value) return;
    hideStatusBar = value;
    _persist(
      'hideStatusBar',
      () => _prefsRepository.saveHideStatusBar(value),
      onSaved: (p) => p.copyWith(hideStatusBar: value),
      restore: (p) => hideStatusBar = p.hideStatusBar,
    );
    notifyListeners();
  }

  void setHeaderInfo(ReaderV2InfoSlots value) {
    if (headerInfo == value) return;
    headerInfo = value;
    _persist(
      'headerInfo',
      () => _prefsRepository.saveHeaderInfo(value),
      onSaved: (p) => p.copyWith(headerInfo: value),
      restore: (p) => headerInfo = p.headerInfo,
    );
    notifyListeners();
  }

  void setFooterInfo(ReaderV2InfoSlots value) {
    if (footerInfo == value) return;
    footerInfo = value;
    _persist(
      'footerInfo',
      () => _prefsRepository.saveFooterInfo(value),
      onSaved: (p) => p.copyWith(footerInfo: value),
      restore: (p) => footerInfo = p.footerInfo,
    );
    notifyListeners();
  }

  double _normalizePagePadding(double value) {
    if (!value.isFinite) return 0.0;
    return value.clamp(minPagePadding, maxPagePadding).toDouble();
  }

  double _normalizeAutoPageSpeed(double value) {
    if (!value.isFinite) return ReaderV2PrefsSnapshot.defaults().autoPageSpeed;
    return value.clamp(minAutoPageSpeed, maxAutoPageSpeed).toDouble();
  }
}
