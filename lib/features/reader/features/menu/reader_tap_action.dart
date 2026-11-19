enum ReaderTapAction {
  menu(0, '喚起選單'),
  nextPage(1, '下一頁'),
  prevPage(2, '上一頁'),
  nextChapter(3, '下一章'),
  prevChapter(4, '上一章'),
  toggleTts(5, '朗讀'),
  openChapters(6, '目錄'),
  toggleAutoPage(7, '自動翻頁'),
  toggleDayNight(8, '日夜切換');

  const ReaderTapAction(this.code, this.label);

  final int code;
  final String label;

  static ReaderTapAction fromCode(int code) {
    for (final action in values) {
      if (action.code == code) {
        return action;
      }
    }
    return ReaderTapAction.menu;
  }

  static List<int> defaultGrid() {
    return List<int>.filled(9, ReaderTapAction.menu.code);
  }
}
