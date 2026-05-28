/// TTF 表結構與條目定義
class DirectoryEntry {
  String tableTag = '';
  int offset = 0;
  int length = 0;
}

class GlyfLayout {
  int numberOfContours = 0;
  int xMin = 0, yMin = 0, xMax = 0, yMax = 0;
  GlyphTableBySimple? glyphSimple;
  List<GlyphTableComponent>? glyphComponent;
}

class GlyphTableBySimple {
  List<int> endPtsOfContours = [];
  int instructionLength = 0;
  List<int> instructions = [];
  List<int> flags = [];
  List<int> xCoordinates = [];
  List<int> yCoordinates = [];
}

class GlyphTableComponent {
  int flags = 0;
  int glyphIndex = 0;
  int argument1 = 0;
  int argument2 = 0;
  double xScale = 1.0;
  double scale01 = 0.0;
  double scale10 = 0.0;
  double yScale = 1.0;
}
