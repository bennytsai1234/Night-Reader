import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_prefs_repository.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_constants.dart';
import 'package:night_reader/shared/theme/app_theme.dart';

class ReaderV2SettingsController extends ChangeNotifier {
  ReaderV2SettingsController({
    ReaderV2PrefsRepository prefsRepository = const ReaderV2PrefsRepository(),
  }) : _prefsRepository = prefsRepository {
    _initFromCache(ReaderV2PrefsRepository.cachedSnapshot);
  }

  static const double minReadableLineHeight =
      ReaderV2Style.minReadableLineHeight;
  static const double minAutoPageSpeed = 0.04;
  static const double maxAutoPageSpeed = 0.45;

  final ReaderV2PrefsRepository _prefsRepository;

  double fontSize = 18.0;
  double lineHeight = 1.5;
  double paragraphSpacing = 1.0;
  double letterSpacing = 0.0;
  int textIndent = 2;
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
      paddingTop: top,
      paddingBottom: bottom,
      paddingLeft: textPadding,
      paddingRight: textPadding,
      bold: false,
      textIndent: textIndent,
    );
  }

  ReadingTheme get currentTheme {
    return _themeAt(themeIndex);
  }

  ReadingTheme get currentMenuTheme {
    return _themeAt(menuThemeIndex);
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

  void setFontSize(double value) {
    fontSize = value;
    unawaited(_prefsRepository.saveFontSize(value));
    notifyListeners();
  }

  void setLineHeight(double value) {
    lineHeight = ReaderV2Style.normalizeLineHeight(value);
    unawaited(_prefsRepository.saveLineHeight(lineHeight));
    notifyListeners();
  }

  void setParagraphSpacing(double value) {
    paragraphSpacing = value;
    unawaited(_prefsRepository.saveParagraphSpacing(value));
    notifyListeners();
  }

  void setLetterSpacing(double value) {
    letterSpacing = value;
    unawaited(_prefsRepository.saveLetterSpacing(value));
    notifyListeners();
  }

  void setTextIndent(int value) {
    textIndent = value;
    unawaited(_prefsRepository.saveTextIndent(value));
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
    _rememberDayNightThemeIndex(themeIndex);
    notifyListeners();
  }

  void setMenuTheme(int value) {
    menuThemeIndex = _normalizeThemeIndex(value);
    unawaited(_prefsRepository.saveMenuThemeIndex(menuThemeIndex));
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

  bool get isCurrentThemeDark => _isThemeDark(themeIndex);

  int get dayNightToggleTargetThemeIndex =>
      isCurrentThemeDark ? lastDayThemeIndex : lastNightThemeIndex;

  bool get willToggleToDarkTheme =>
      _isThemeDark(dayNightToggleTargetThemeIndex);

  String get dayNightToggleTooltip =>
      willToggleToDarkTheme ? '切換到夜間主題' : '切換到白天主題';

  IconData get dayNightToggleIcon =>
      willToggleToDarkTheme
          ? Icons.dark_mode_rounded
          : Icons.light_mode_rounded;

  void toggleDayNightTheme() {
    final target = dayNightToggleTargetThemeIndex;
    if (target == themeIndex) {
      final fallback =
          isCurrentThemeDark
              ? _fallbackDayThemeIndex()
              : _fallbackNightThemeIndex();
      if (fallback != themeIndex) setTheme(fallback);
      return;
    }
    setTheme(target);
  }

  void _rememberDayNightThemeIndex(int index) {
    if (_isThemeDark(index)) {
      lastNightThemeIndex = index;
      unawaited(_prefsRepository.saveNightThemeIndex(index));
    } else {
      lastDayThemeIndex = index;
      unawaited(_prefsRepository.saveDayThemeIndex(index));
    }
  }

  bool _isThemeDark(int index) {
    if (AppTheme.readingThemes.isEmpty) return index != 0;
    return AppTheme.readingThemes[_normalizeThemeIndex(index)].backgroundColor
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

  int _fallbackDayThemeIndex() {
    if (AppTheme.readingThemes.isEmpty) return 0;
    for (var i = 0; i < AppTheme.readingThemes.length; i++) {
      if (!_isThemeDark(i)) return i;
    }
    return 0;
  }

  int _fallbackNightThemeIndex() {
    if (AppTheme.readingThemes.isEmpty) return 1;
    for (var i = AppTheme.readingThemes.length - 1; i >= 0; i--) {
      if (_isThemeDark(i)) return i;
    }
    return (AppTheme.readingThemes.length - 1).clamp(0, 1 << 20).toInt();
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
    _rememberDayNightThemeIndex(themeIndex);
    if (_isThemeDark(lastDayThemeIndex)) {
      lastDayThemeIndex = _fallbackDayThemeIndex();
    }
    if (!_isThemeDark(lastNightThemeIndex)) {
      lastNightThemeIndex = _fallbackNightThemeIndex();
    }
  }
}
