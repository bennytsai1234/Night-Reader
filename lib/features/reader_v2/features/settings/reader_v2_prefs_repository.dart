import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_tap_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReaderV2PrefsSnapshot {
  final double fontSize;
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

  const ReaderV2PrefsSnapshot({
    required this.fontSize,
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
  });

  factory ReaderV2PrefsSnapshot.defaults() {
    return ReaderV2PrefsSnapshot(
      fontSize: 18.0,
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
    );
  }

  ReaderV2PrefsSnapshot copyWith({
    double? fontSize,
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
  }) {
    return ReaderV2PrefsSnapshot(
      fontSize: fontSize ?? this.fontSize,
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
    );
  }
}

class ReaderV2PrefsRepository {
  const ReaderV2PrefsRepository();

  static ReaderV2PrefsSnapshot? _latestSnapshot;

  static ReaderV2PrefsSnapshot get cachedSnapshot =>
      _latestSnapshot ?? ReaderV2PrefsSnapshot.defaults();

  Future<ReaderV2PrefsSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final defaults = ReaderV2PrefsSnapshot.defaults();
    final themeIndex =
        prefs.getInt(PreferKey.readerThemeIndex) ?? defaults.themeIndex;
    final snapshot = ReaderV2PrefsSnapshot(
      fontSize: prefs.getDouble(PreferKey.readerFontSize) ?? defaults.fontSize,
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
    );
    _latestSnapshot = snapshot;
    return snapshot;
  }

  Future<void> saveFontSize(double value) {
    return _setDouble(PreferKey.readerFontSize, value);
  }

  Future<void> saveLineHeight(double value) {
    return _setDouble(PreferKey.readerLineHeight, value);
  }

  Future<void> saveParagraphSpacing(double value) {
    return _setDouble(PreferKey.readerParagraphSpacing, value);
  }

  Future<void> saveLetterSpacing(double value) {
    return _setDouble(PreferKey.readerLetterSpacing, value);
  }

  Future<void> saveTextIndent(int value) {
    return _setInt(PreferKey.readerTextIndent, value);
  }

  Future<void> saveThemeIndex(int value) {
    return _setInt(PreferKey.readerThemeIndex, value);
  }

  Future<void> saveDayThemeIndex(int value) {
    return _setInt(PreferKey.readerDayThemeIndex, value);
  }

  Future<void> saveNightThemeIndex(int value) {
    return _setInt(PreferKey.readerNightThemeIndex, value);
  }

  Future<void> saveMenuThemeIndex(int value) {
    return _setInt(PreferKey.readerMenuThemeIndex, value);
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

  List<int> parseClickActions(String? stored) {
    return _parseClickActions(stored);
  }

  List<int> normalizeClickActions(List<int> actions) {
    return _normalizeClickActions(actions);
  }

  Future<void> _setDouble(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
  }

  Future<void> _setInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  Future<void> _setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _setString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
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

  double _normalizeAutoPageSpeed(double? value) {
    if (value == null || !value.isFinite)
      return ReaderV2PrefsSnapshot.defaults().autoPageSpeed;
    if (value > 1) return (value / 100).clamp(0.08, 0.45).toDouble();
    return value.clamp(0.08, 0.45).toDouble();
  }
}
