import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/source_switch/same_book.dart';

/// 手動換源與單章借源的「校驗作者」照 Legado `ChangeBookSourceViewModel`：
/// 搜到的作者「含」這本書的作者就算；自動換源照 ADR 0069 要完全一樣。
void main() {
  test('校驗作者時，搜到的作者含這本書的作者就列', () {
    bool match(String author) => isChangeSourceMatch(
      '雪中悍刀行',
      author,
      '雪中悍刀行',
      '烽火戲諸侯',
      checkAuthor: true,
    );
    expect(match('烽火戲諸侯'), isTrue);
    expect(match('烽火戲諸侯（著）'), isTrue);
    expect(match('烽火戲諸侯／某人'), isTrue);
    expect(match('某人'), isFalse);
    expect(match(''), isFalse);
  });

  test('不校驗作者時只比書名', () {
    expect(
      isChangeSourceMatch('雪中悍刀行', '某人', '雪中悍刀行', '烽火戲諸侯', checkAuthor: false),
      isTrue,
    );
    expect(
      isChangeSourceMatch(
        '雪中悍刀行外傳',
        '烽火戲諸侯',
        '雪中悍刀行',
        '烽火戲諸侯',
        checkAuthor: true,
      ),
      isFalse,
    );
  });

  test('自動換源仍要作者完全一樣（ADR 0069）', () {
    expect(
      isSameBook('雪中悍刀行', '烽火戲諸侯（著）', '雪中悍刀行', '烽火戲諸侯', checkAuthor: true),
      isFalse,
    );
  });
}
