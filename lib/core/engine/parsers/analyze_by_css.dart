import 'css/analyze_by_css_base.dart';

export 'css/analyze_by_css_base.dart';
export 'css/analyze_by_css_core.dart';
export 'css/analyze_by_css_helper.dart';

/// AnalyzeByCss - CSS 選擇器解析器 (重構後)
class AnalyzeByCss extends AnalyzeByCssBase {
  AnalyzeByCss([dynamic doc]) {
    if (doc != null) {
      setContent(doc);
    }
  }
}
