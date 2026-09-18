import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/local_book/local_book_formats.dart';

void main() {
  test('本地書格式只接受 TXT', () {
    expect(kSupportedLocalBookExtensions, <String>{'txt'});
    expect(isSupportedLocalBookExtension('txt'), isTrue);
    expect(isSupportedLocalBookExtension('.TXT'), isTrue);
    expect(isSupportedLocalBookExtension('epub'), isFalse);
  });

  test('本地書路徑會忽略 local scheme 並檢查副檔名', () {
    expect(isSupportedLocalBookPath(r'local://C:\books\novel.TXT'), isTrue);
    expect(isSupportedLocalBookPath(r'local://C:\books\novel.epub'), isFalse);
    expect(isSupportedLocalBookPath('local://book-without-extension'), isFalse);
  });
}
