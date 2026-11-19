import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/sync/ai_find_sync.dart';
import 'package:night_reader/core/sync/bookmark_sync.dart';
import 'package:night_reader/core/sync/highlight_sync.dart';
import 'package:night_reader/core/sync/login_data_sync.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/core/sync/replace_rule_sync.dart';
import 'package:night_reader/core/sync/source_sync.dart';
import 'package:night_reader/features/settings/sync_status_text.dart';

void main() {
  test('every kind a full sync goes through has its own name in the progress '
      'line', () {
    final names = [
      ProgressSync.kind,
      SourceSync.kind,
      ReplaceRuleSync.kind,
      'bookshelf',
      BookmarkSync.kind,
      HighlightSync.kind,
      AiFindSync.kind,
      'read_stats',
      'settings',
      for (final kind in LoginDataSync.kinds()) kind.name,
    ];

    for (final name in names) {
      expect(syncKindLabel(name), isNot('資料'), reason: name);
    }
    expect(syncKindLabel(AiFindSync.kind), '過去的找書');
  });
}
