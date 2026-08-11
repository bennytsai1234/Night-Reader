import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
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
  static const double minAutoPageSpeed = ReaderV2PrefsRepository.minAutoPageSpeed;
  static const double maxAutoPageSpeed = ReaderV2PrefsRepository.maxAutoPageSpeed;

  final ReaderV2PrefsRepository _prefsRepository;

  double fontSize = 18.0;
  double lineHeight = 1.5;
  double paragraphSpacing = 1.0;
  double letterSpacing = 0.0;
  int textIndent = 2;
  bool lastLineSpacingCompensation = false;
  double textPadding = 16.0;
  int themeIndex = 0;
  int lastDayThemeIndex = 0;
  int lastNightThemeIndex = 1;
  int menuThemeIndex = 0;
  int chineseConvert = 0;
  double autoPageSpeed = ReaderV2PrefsSnapshot.defaults().autoPageSpeed;
  bool showAddToShelfAlert = true;
  List<int> clickActions = ReaderV2PrefsSnapshot.defaults().clickActions;
  int _contentSettingsGeneration = 0;

  int get contentSettingsGeneration => _contentSettingsGeneration;
  bool get showReadTitleAddition => true;

  Future<void> loadSettings() async {
    final snapshot = await _prefsRepository.load();
    _initFromCache(snapshot);
    _normalizeDayNightThemeIndexes();
    notifyListeners();
  }

  void _initFromCache(ReaderV2PrefsSnapshot snapshot) {
    fontSize = snapshot.fontSize;
    lineHeight = ReaderV2Style.normalizeLineHeight(snapshot.lineHeight);
    paragraphSpacing = snapshot.paragraphSpacing;
    letterSpacing = snapshot.letterSpacing;
    textIndent = snapshot.textIndent;
    lastLineSpacingCompensation = snapshot.lastLineSpacingCompensation;
    themeIndex = _normalizeThemeIndex(snapshot.themeIndex);
    autoPageSpeed = _normalizeAutoPageSpeed(snapshot.autoPageSpeed);
    chineseConvert = snapshot.chineseConvert;
    showAddToShelfAlert = snapshot.showAddToShelfAlert;
    menuThemeIndex = _normalizeThemeIndex(snapshot.menuThemeIndex);
    clickActions = List<int>.from(snapshot.clickActions);
    lastDayThemeIndex = snapshot.lastDayThemeIndex;
    lastNightThemeIndex = snapshot.lastNightThemeIndex;
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
      paddingLeft: textPadding,
      paddingRight: textPadding,
      bold: false,
      textIndent: textIndent,
      lastLineSpacingCompensation: lastLineSpacingCompensation,
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
      unawaited(_prefsRepository.saveFontSize(fontSize));
    }
    if (lineHeight != null) {
      final normalized = ReaderV2Style.normalizeLineHeight(lineHeight);
      if (this.lineHeight != normalized) {
        this.lineHeight = normalized;
        changed = true;
      }
      unawaited(_prefsRepository.saveLineHeight(normalized));
    }
    if (paragraphSpacing != null) {
      if (this.paragraphSpacing != paragraphSpacing) {
        this.paragraphSpacing = paragraphSpacing;
        changed = true;
      }
      unawaited(_prefsRepository.saveParagraphSpacing(paragraphSpacing));
    }
    if (letterSpacing != null) {
      if (this.letterSpacing != letterSpacing) {
        this.letterSpacing = letterSpacing;
        changed = true;
      }
      unawaited(_prefsRepository.saveLetterSpacing(letterSpacing));
    }
    if (changed) notifyListeners();
  }

  void setTextIndent(int value) {
    textIndent = value;
    unawaited(_prefsRepository.saveTextIndent(value));
    notifyListeners();
  }

  void setLastLineSpacingCompensation(bool value) {
    if (lastLineSpacingCompensation == value) return;
    lastLineSpacingCompensation = value;
    unawaited(_prefsRepository.saveLastLineSpacingCompensation(value));
    notifyListeners();
  }

  void setAutoPageSpeed(double value) {
    final normalized = _normalizeAutoPageSpeed(value);
    if ((autoPageSpeed - normalized).abs() < 0.001) return;
    autoPageSpeed = normalized;
    unawaited(_prefsRepository.saveAutoPageSpeed(normalized));
    notifyListeners();
  }

  void setTheme(int value) {
    themeIndex = _normalizeThemeIndex(value);
    unawaited(_prefsRepository.saveThemeIndex(themeIndex));
    if (isReaderDarkMode) {
      lastNightThemeIndex = themeIndex;
      unawaited(_prefsRepository.saveNightThemeIndex(themeIndex));
    } else {
      lastDayThemeIndex = themeIndex;
      unawaited(_prefsRepository.saveDayThemeIndex(themeIndex));
    }
    notifyListeners();
  }

  void setMenuTheme(int value) {
    menuThemeIndex = _normalizeThemeIndex(value);
    unawaited(_prefsRepository.saveMenuThemeIndex(menuThemeIndex));
    ThemeSettingsProvider.saveMenuBuiltInIndex(isMenuDarkMode, menuThemeIndex);
    notifyListeners();
  }

  void setChineseConvert(int value) {
    if (chineseConvert == value) return;
    chineseConvert = value;
    _contentSettingsGeneration += 1;
    unawaited(_prefsRepository.saveChineseConvert(value));
    notifyListeners();
  }

  void setClickAction(int zone, int action) {
    if (zone < 0 || zone >= clickActions.length) return;
    clickActions[zone] = action;
    unawaited(_prefsRepository.saveClickActions(clickActions));
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
