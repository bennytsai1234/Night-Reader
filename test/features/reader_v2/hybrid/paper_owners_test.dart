// 閱讀器的紙歸誰管（PaperOwners）：等正文的跳章、進行中的還原、重新還原
// 最後的穩定位置；都沒有、也沒有操作時紙才沒人用。
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/paper_owners.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_operation_token.dart';

ReaderV2OperationToken _jump(int id) => ReaderV2OperationToken(
  id: id,
  kind: ReaderV2OperationKind.jump,
  layoutGeneration: 0,
  targetLocation: const ReaderV2Location(chapterIndex: 3, charOffset: 0),
);

void main() {
  test('a jump covers the paper only once text is shown', () {
    final owners = PaperOwners();
    // 開書還沒排好：紙本來就蓋著，跳章不另外蓋。
    expect(owners.claimForJump(_jump(1), textShown: false), isFalse);
    expect(owners.holdsTextForJump, isFalse);

    final jump = _jump(2);
    expect(owners.claimForJump(jump, textShown: true), isTrue);
    expect(owners.holdsTextForJump, isTrue);
    // 同一個跳章重複通知不重來。
    expect(owners.claimForJump(jump, textShown: true), isFalse);
    expect(owners.holdsTextForJump, isTrue);

    // 跳章結束（目前沒有跳章）就放手。
    expect(owners.claimForJump(null, textShown: true), isFalse);
    expect(owners.holdsTextForJump, isFalse);
  });

  test('the restore takes over the jump once layout starts', () {
    final owners = PaperOwners()..claimForJump(_jump(1), textShown: true);
    bool current() => true;
    owners.beginRestore(current);
    // 取正文的那段時間跳章還算數。
    expect(owners.holdsTextForJump, isTrue);
    expect(owners.restoring, isTrue);

    owners.restoreTookOverJump();
    expect(owners.holdsTextForJump, isFalse);
    expect(owners.isFree(hasOperation: false), isFalse);

    owners.endRestore(current);
    expect(owners.isFree(hasOperation: false), isTrue);
  });

  test(
    'a superseded restore neither holds the paper nor clears its successor',
    () {
      final owners = PaperOwners();
      var firstCurrent = true;
      bool first() => firstCurrent;
      bool second() => true;
      owners.beginRestore(first);
      firstCurrent = false;
      // 作廢的還原不算在管。
      expect(owners.restoring, isFalse);

      owners
        ..beginRestore(second)
        // 舊的那次晚一點才結束，不能把新的清掉。
        ..endRestore(first);
      expect(owners.restoring, isTrue);
      owners.endRestore(second);
      expect(owners.restoring, isFalse);
    },
  );

  test('re-restoring the stable world runs once and wraps its restore', () {
    final owners = PaperOwners();
    expect(owners.beginStableWorld(), isTrue);
    expect(owners.beginStableWorld(), isFalse);
    bool current() => true;
    owners
      ..beginRestore(current)
      ..endRestore(current);
    // 裡面那次還原結束了，重新還原還沒結束：紙還不是沒人用。
    expect(owners.isFree(hasOperation: false), isFalse);
    owners.endStableWorld();
    expect(owners.isFree(hasOperation: false), isTrue);
    // 有操作在跑時一律不算沒人用。
    expect(owners.isFree(hasOperation: true), isFalse);
  });
}
