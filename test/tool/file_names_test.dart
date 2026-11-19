import 'package:flutter_test/flutter_test.dart';

import '../../tool/file_names.dart';

void main() {
  group('fileNameMismatch', () {
    test('檔名是類別名稱的小寫寫法就對得上', () {
      expect(fileNameMismatch('login_wall', 'class LoginWall {}'), isNull);
      expect(
        fileNameMismatch('webdav_sync_store', 'class WebDavSyncStore {}'),
        isNull,
      );
    });

    test('檔名是類別名稱的前幾個詞、或類別名稱是檔名的前幾個詞，都對得上', () {
      expect(fileNameMismatch('glass', 'class GlassSurface {}'), isNull);
      expect(
        fileNameMismatch('reader_page_shell', 'class ReaderPage {}'),
        isNull,
      );
      expect(fileNameMismatch('sync_records', 'class SyncRecord {}'), isNull);
    });

    test('前綴切在一個詞中間就對不上', () {
      expect(fileNameMismatch('user', 'class UsernameDialog {}'), [
        'UsernameDialog',
      ]);
      expect(fileNameMismatch('login_wall_x', 'class LoginWal {}'), [
        'LoginWal',
      ]);
    });

    test('註解裡的 class 不算宣告', () {
      expect(
        fileNameMismatch('reader', '''
/*
class Reader {}
*/
// class Reader {}
class BookCard {}
'''),
        ['BookCard'],
      );
    });

    test('沒有名字的 extension 不算公開型別', () {
      expect(
        fileNameMismatch('trimmed_string', 'extension on String {}'),
        isNull,
      );
    });

    test('part of 的檔不看', () {
      expect(
        fileNameMismatch('x', "part of 'y.dart';\nclass Other {}"),
        isNull,
      );
    });
  });

  test('掃描路徑換成 repo 相對、正斜線的寫法', () {
    expect(repoRelative('lib/core'), 'lib/core');
    expect(repoRelative('./lib/core/'), 'lib/core');
    expect(repoRelative(r'lib\core\ai_find'), 'lib/core/ai_find');
    expect(repoRelative('/repo/lib/core', root: '/repo'), 'lib/core');
    expect(repoRelative(r'C:\repo\lib\core', root: r'C:\repo'), 'lib/core');
  });

  test('看過的清單只歸目錄底下的檔', () {
    expect(isUnder('lib/core/ai_find/ai_find_prompt.dart', 'lib/core'), isTrue);
    expect(isUnder('lib/core_extra/a.dart', 'lib/core'), isFalse);
    expect(isUnder('lib/main.dart', 'lib'), isTrue);
  });
}
