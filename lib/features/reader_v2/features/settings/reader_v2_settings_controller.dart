import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_highlight_style.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_info_item.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_prefs_repository.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_constants.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';
import 'package:night_reader/shared/theme/app_theme.dart';

class ReaderV2SettingsController extends ChangeNotifier {
  ReaderV2SettingsController({
    ReaderV2PrefsRepository prefsRepository = const ReaderV2PrefsRepository(),
  }) : _prefsRepository = prefsRepository {
    _initFromCache(ReaderV2PrefsRepository.cachedSnapshot);
  }

  static const double minReadableLineHeight = ReaderV2Style.minReadableLineHeight;
  static const double maxReadableLineHeight = ReaderV2Style.maxReadableLineHeight;
  static const double minAutoPageSpeed = ReaderV2PrefsRepository.minAutoPageSpeed;
  static const double maxAutoPageSpeed = ReaderV2PrefsRepository.maxAutoPageSpeed;
  static const double minPagePadding = ReaderV2PrefsRepository.minPagePadding;
  static const double maxPagePadding = ReaderV2PrefsRepository.maxPagePadding;

  final ReaderV2PrefsRepository _prefsRepository;

  double fontSize = 18.0;
  double titleFontSize = 18.0 + kReaderV2DefaultTitleSizeDelta;
  double lineHeight = 1.5;
  double paragraphSpacing = 1.0;
  double letterSpacing = 0.0;
  int textIndent = 2;
  double paddingHorizontal = 16.0;
  double paddingTop = 0.0;
  double paddingBottom = 0.0;
  bool hideStatusBar = false;
  ReaderV2InfoSlots headerInfo = ReaderV2PrefsSnapshot.defaults().headerInfo;
  ReaderV2InfoSlots footerInfo = ReaderV2PrefsSnapshot.defaults().footerInfo;
  int themeIndex = 0;
  int lastDayThemeIndex = 0;
  int lastNightThemeIndex = 1;
  int menuThemeIndex = 0;
  int chineseConvert = 0;
  double autoPageSpeed = ReaderV2PrefsSnapshot.defaults().autoPageSpeed;
  bool showAddToShelfAlert = true;
  List<int> clickActions = ReaderV2PrefsSnapshot.defaults().clickActions;
  ReaderV2HighlightColor highlightColor =
      ReaderV2PrefsSnapshot.defaults().highlightColor;
  double highlightStrength = ReaderV2PrefsSnapshot.defaults().highlightStrength;
  int _contentSettingsGeneration = 0;

  /// 最後一次確定落地（載入或保存成功）的設定；保存失敗時據此還原。
  ReaderV2PrefsSnapshot _persisted = ReaderV2PrefsRepository.cachedSnapshot;
  final Map<String, int> _saveGenerations = <String, int>{};
  final StreamController<String> _saveFailures =
      StreamController<String>.broadcast();
  bool _disposed = false;

  /// 設定保存失敗（已還原為先前的值）時發出的提示訊息。
  Stream<String> get saveFailures => _saveFailures.stream;

  int get contentSettingsGeneration => _contentSettingsGeneration;
  bool get showReadTitleAddition => true;

  Future<void> loadSettings() async {
    final snapshot = await _prefsRepository.load();
    _persisted = snapshot;
    // 別處（例如「閱讀偏好」頁）改了繁簡轉換時，重新載入也必須讓正文重轉。
    if (snapshot.chineseConvert != chineseConvert) {
      _contentSettingsGeneration += 1;
    }
    _initFromCache(snapshot);
    ChineseDisplay.mode.value = chineseConvert;
    _normalizeDayNightThemeIndexes();
    notifyListeners();
  }

  void _initFromCache(ReaderV2PrefsSnapshot snapshot) {
    fontSize = snapshot.fontSize;
    titleFontSize = snapshot.titleFontSize;
    lineHeight = ReaderV2Style.normalizeLineHeight(snapshot.lineHeight);
    paragraphSpacing = snapshot.paragraphSpacing;
    letterSpacing = snapshot.letterSpacing;
    textIndent = snapshot.textIndent;
    themeIndex = _normalizeThemeIndex(snapshot.themeIndex);
    autoPageSpeed = _normalizeAutoPageSpeed(snapshot.autoPageSpeed);
    chineseConvert = snapshot.chineseConvert;
    showAddToShelfAlert = snapshot.showAddToShelfAlert;
    menuThemeIndex = _normalizeThemeIndex(snapshot.menuThemeIndex);
    clickActions = List<int>.from(snapshot.clickActions);
    lastDayThemeIndex = snapshot.lastDayThemeIndex;
    lastNightThemeIndex = snapshot.lastNightThemeIndex;
    paddingHorizontal = snapshot.paddingHorizontal;
    paddingTop = snapshot.paddingTop;
    paddingBottom = snapshot.paddingBottom;
    hideStatusBar = snapshot.hideStatusBar;
    headerInfo = snapshot.headerInfo;
    footerInfo = snapshot.footerInfo;
    highlightColor = snapshot.highlightColor;
    highlightStrength = snapshot.highlightStrength;
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
        (topInfoReservedExternally ? 0.0 : mediaPadding.top * kReaderContentTopSafeAreaFactor) +
        kReaderContentTopSpacing;
    final bottom = bottomInfoReservedExternally ? 0.0 : mediaPadding.bottom;
    return ReaderV2Style(
      fontSize: fontSize,
      lineHeight: ReaderV2Style.normalizeLineHeight(lineHeight),
      letterSpacing: letterSpacing,
      paragraphSpacing: paragraphSpacing,
      paddingTop: top,
      paddingBottom: bottom,
      paddingLeft: paddingHorizontal,
      paddingRight: paddingHorizontal,
      bold: false,
      textIndent: textIndent,
      titleFontSize: titleFontSize,
    );
  }

  bool get isReaderDarkMode => ThemeSettingsProvider.resolveAreaDarkMode(
        ThemeArea.reader,
        fallback: _isThemeDark(themeIndex),
      );

  bool get isMenuDarkMode => ThemeSettingsProvider.resolveAreaDarkMode(
        ThemeArea.menu,
        fallback: isReaderDarkMode,
      );

  ReadingTheme get currentTheme {
    final dark = isReaderDarkMode;
    final index = dark ? lastNightThemeIndex : lastDayThemeIndex;
    return ThemeSettingsProvider.resolveReaderTheme(
      dark: dark,
      menu: false,
      fallback: _themeAt(index),
    );
  }

  ReadingTheme get currentMenuTheme {
    final dark = isMenuDarkMode;
    final index = _normalizeThemeIndex(
      ThemeSettingsProvider.menuBuiltInIndex(dark, menuThemeIndex),
    );
    return ThemeSettingsProvider.resolveReaderTheme(
      dark: dark,
      menu: true,
      fallback: _themeAt(index),
    );
  }

  ReadingTheme _themeAt(int index) {
    if (AppTheme.readingThemes.isEmpty) {
      return ReadingTheme(
        name: 'fallback',
        backgroundColor: Colors.white,
        textColor: const Color(0xFF1A1A1A),
      );
    }
    return AppTheme.readingThemes[_normalizeThemeIndex(index)];
  }

  void setFontSize(double value) => setTypography(fontSize: value);
  void setLineHeight(double value) => setTypography(lineHeight: value);
  void setParagraphSpacing(double value) => setTypography(paragraphSpacing: value);
  void setLetterSpacing(double value) => setTypography(letterSpacing: value);

  void setTypography({
    double? fontSize,
    double? titleFontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? letterSpacing,
  }) {
    var changed = false;
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

  /// 將字號、行高、字距、段距與首行縮排恢復為預設值。
  void resetTypography() {
    final defaults = ReaderV2PrefsSnapshot.defaults();
    setTypography(
      fontSize: defaults.fontSize,
      titleFontSize: defaults.titleFontSize,
      lineHeight: defaults.lineHeight,
      paragraphSpacing: defaults.paragraphSpacing,
      letterSpacing: defaults.letterSpacing,
    );
    if (textIndent != defaults.textIndent) setTextIndent(defaults.textIndent);
  }

  void setTextIndent(int value) {
    textIndent = value;
    _persist(
      'textIndent',
      () => _prefsRepository.saveTextIndent(value),
      onSaved: (p) => p.copyWith(textIndent: value),
      restore: (p) => textIndent = p.textIndent,
    );
    notifyListeners();
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

  /// 目前閱讀主題下實際的高亮色。
  Color get resolvedHighlightColor =>
      highlightColor.resolve(currentTheme.textColor);

  void setTheme(int value) {
    final next = _normalizeThemeIndex(value);
    themeIndex = next;
    final night = isReaderDarkMode;
    if (night) {
      lastNightThemeIndex = next;
    } else {
      lastDayThemeIndex = next;
    }
    _persist(
      'theme',
      () => Future.wait<void>([
        _prefsRepository.saveThemeIndex(next),
        night
            ? _prefsRepository.saveNightThemeIndex(next)
            : _prefsRepository.saveDayThemeIndex(next),
      ]),
      onSaved: (p) => night
          ? p.copyWith(themeIndex: next, lastNightThemeIndex: next)
          : p.copyWith(themeIndex: next, lastDayThemeIndex: next),
      restore: (p) {
        themeIndex = _normalizeThemeIndex(p.themeIndex);
        lastDayThemeIndex = p.lastDayThemeIndex;
        lastNightThemeIndex = p.lastNightThemeIndex;
      },
    );
    notifyListeners();
  }

  void setMenuTheme(int value) {
    final next = _normalizeThemeIndex(value);
    menuThemeIndex = next;
    _persist(
      'menuTheme',
      () => _prefsRepository.saveMenuThemeIndex(next),
      onSaved: (p) => p.copyWith(menuThemeIndex: next),
      restore: (p) => menuThemeIndex = _normalizeThemeIndex(p.menuThemeIndex),
    );
    ThemeSettingsProvider.saveMenuBuiltInIndex(isMenuDarkMode, menuThemeIndex);
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

  /// 將邊距、狀態列與頁首／頁尾恢復為預設值。
  void resetPageLayout() {
    final defaults = ReaderV2PrefsSnapshot.defaults();
    setPagePadding(
      horizontal: defaults.paddingHorizontal,
      top: defaults.paddingTop,
      bottom: defaults.paddingBottom,
    );
    setHideStatusBar(defaults.hideStatusBar);
    setHeaderInfo(defaults.headerInfo);
    setFooterInfo(defaults.footerInfo);
  }

  bool get isPageLayoutDefault {
    final defaults = ReaderV2PrefsSnapshot.defaults();
    return paddingHorizontal == defaults.paddingHorizontal &&
        paddingTop == defaults.paddingTop &&
        paddingBottom == defaults.paddingBottom &&
        hideStatusBar == defaults.hideStatusBar &&
        headerInfo == defaults.headerInfo &&
        footerInfo == defaults.footerInfo;
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

  bool get isCurrentThemeDark => isReaderDarkMode;

  bool get willToggleToDarkTheme => !isReaderDarkMode;

  String get dayNightToggleTooltip =>
      willToggleToDarkTheme ? '切換閱讀深色模式' : '切換閱讀淺色模式';

  IconData get dayNightToggleIcon =>
      willToggleToDarkTheme ? Icons.dark_mode_rounded : Icons.light_mode_rounded;

  void toggleDayNightTheme() {
    ThemeSettingsProvider.saveAreaMode(
      ThemeArea.reader,
      isReaderDarkMode ? AreaThemeMode.light : AreaThemeMode.dark,
    );
    notifyListeners();
  }

  bool _isThemeDark(int index) {
    if (AppTheme.readingThemes.isEmpty) return index != 0;
    return AppTheme.readingThemes[_normalizeThemeIndex(index)]
            .backgroundColor
            .computeLuminance() <
        0.5;
  }

  int _normalizeThemeIndex(int index) {
    if (AppTheme.readingThemes.isEmpty) return index;
    return index.clamp(0, AppTheme.readingThemes.length - 1).toInt();
  }

  double _normalizePagePadding(double value) {
    if (!value.isFinite) return 0.0;
    return value.clamp(minPagePadding, maxPagePadding).toDouble();
  }

  double _normalizeAutoPageSpeed(double value) {
    if (!value.isFinite) return ReaderV2PrefsSnapshot.defaults().autoPageSpeed;
    return value.clamp(minAutoPageSpeed, maxAutoPageSpeed).toDouble();
  }

  void _normalizeDayNightThemeIndexes() {
    if (AppTheme.readingThemes.isEmpty) {
      lastDayThemeIndex = 0;
      lastNightThemeIndex = 1;
      return;
    }
    lastDayThemeIndex =
        lastDayThemeIndex.clamp(0, AppTheme.readingThemes.length - 1).toInt();
    lastNightThemeIndex =
        lastNightThemeIndex.clamp(0, AppTheme.readingThemes.length - 1).toInt();
  }
}
