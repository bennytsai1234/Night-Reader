import 'ttf_tables.dart';

/// QueryTTF 的基礎類別
abstract class QueryTTFBase {
  final Map<int, String> unicodeToGlyph = {};
  final Map<String, int> glyphToUnicode = {};
  final Map<int, int> unicodeToGlyphId = {};

  final Map<String, DirectoryEntry> directorys = {};
  int headIndexToLocFormat = 0;
  int maxpNumGlyphs = 0;
  int maxpMaxContours = 0;
  List<int> loca = [];
  List<GlyfLayout?> glyfArray = [];

  int getGlyfIdByUnicode(int unicode) {
    return unicodeToGlyphId[unicode] ?? 0;
  }

  String? getGlyfByUnicode(int unicode) {
    return unicodeToGlyph[unicode];
  }

  int getUnicodeByGlyf(String? glyph) {
    if (glyph == null) return 0;
    return glyphToUnicode[glyph] ?? 0;
  }

  bool isBlankUnicode(int unicode) {
    switch (unicode) {
      case 0x0009:
      case 0x0020:
      case 0x00A0:
      case 0x2002:
      case 0x2003:
      case 0x2007:
      case 0x200A:
      case 0x200B:
      case 0x200C:
      case 0x200D:
      case 0x202F:
      case 0x205F:
        return true;
      default:
        return false;
    }
  }
}
