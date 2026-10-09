import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book_source.dart';

void main() {
  test('groups split on commas and semicolons but keep spaces', () {
    expect(splitSourceGroups('🔥 精選, 男頻；女頻;，'), {'🔥 精選', '男頻', '女頻'});
    expect(splitSourceGroups(null), isEmpty);
  });

  test('adding and removing a group keeps names with spaces whole', () {
    final source = BookSource(bookSourceUrl: 'u', bookSourceGroup: '🔥 精選')
      ..addGroup('科幻 小說');
    expect(source.groupTags, {'🔥 精選', '科幻 小說'});

    source.removeGroup('🔥 精選');
    expect(source.bookSourceGroup, '科幻 小說');
  });
}
