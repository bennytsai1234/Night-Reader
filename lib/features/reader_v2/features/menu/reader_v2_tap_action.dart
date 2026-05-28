enum ReaderV2TapAction {
  menu(0, '喚起選單'),
  nextPage(1, '下一頁'),
  prevPage(2, '上一頁'),
  nextChapter(3, '下一章'),
  prevChapter(4, '上一章'),
  toggleTts(5, '朗讀'),
  bookmark(7, '加入書籤');

  const ReaderV2TapAction(this.code, this.label);

  final int code;
  final String label;

  static ReaderV2TapAction fromCode(int code) {
    for (final action in values) {
      if (action.code == code) {
        return action;
      }
    }
    return ReaderV2TapAction.menu;
  }

  static List<int> defaultGrid() {
    return List<int>.filled(9, ReaderV2TapAction.menu.code);
  }
}
