import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/sync/sync_records.dart';

SyncRecord _rec(int position, int time) =>
    SyncRecord(time: time, data: {'charOffset': position});

SyncBaseEntry _base(SyncRecord local, SyncRecord remote) => SyncBaseEntry(
  local: local.fingerprint,
  remote: remote.fingerprint,
  time: remote.time,
);

void main() {
  group('decideSync', () {
    final synced = _rec(10, 100);
    final base = _base(synced, synced);

    test('opening a book bumps its time but is not a change', () {
      // 開書沒翻頁也會更新時間；內容一樣就不算改過，雲端別台的新進度照樣套用。
      final reopened = _rec(10, 900);
      final remote = _rec(50, 500);
      expect(
        decideSync(local: reopened, remote: remote, base: base),
        SyncDecision.apply,
      );
    });

    test('only this phone changed: upload', () {
      expect(
        decideSync(local: _rec(20, 200), remote: synced, base: base),
        SyncDecision.upload,
      );
    });

    test('both changed: the newer one wins', () {
      expect(
        decideSync(local: _rec(20, 300), remote: _rec(30, 200), base: base),
        SyncDecision.upload,
      );
      expect(
        decideSync(local: _rec(20, 200), remote: _rec(30, 300), base: base),
        SyncDecision.apply,
      );
    });

    test('never synced and different: the newer one wins', () {
      expect(
        decideSync(local: _rec(1, 5), remote: _rec(2, 9), base: null),
        SyncDecision.apply,
      );
      expect(
        decideSync(local: _rec(1, 9), remote: _rec(2, 5), base: null),
        SyncDecision.upload,
      );
    });

    test('same content is in sync whatever the times', () {
      expect(
        decideSync(local: _rec(1, 5), remote: _rec(1, 9), base: null),
        SyncDecision.same,
      );
    });

    test('remote went back to an older write: write this phone again', () {
      // 這台上傳了 20（時間 200），別台同時寫入、把雲端蓋回舊的 10。
      final uploaded = _rec(20, 200);
      expect(
        decideSync(
          local: uploaded,
          remote: synced,
          base: _base(uploaded, uploaded),
        ),
        SyncDecision.upload,
      );
    });

    test('a mapped chapter index stays in sync', () {
      // 套用雲端的進度時章節序號照這台目錄對過，本機的指紋和雲端不同。
      final remote = _rec(30, 300);
      final applied = _rec(31, 300);
      expect(
        decideSync(
          local: applied,
          remote: remote,
          base: _base(applied, remote),
        ),
        SyncDecision.same,
      );
    });

    test('missing on one side', () {
      expect(
        decideSync(local: synced, remote: null, base: base),
        SyncDecision.upload,
      );
      expect(
        decideSync(local: null, remote: synced, base: null),
        SyncDecision.apply,
      );
      expect(
        decideSync(local: null, remote: synced, base: base),
        SyncDecision.same,
      );
    });
  });

  test('fingerprints ignore key order and time', () {
    final a = SyncRecord(time: 1, data: {'a': 1, 'b': 'x'});
    final b = SyncRecord(time: 2, data: {'b': 'x', 'a': 1});
    expect(a.fingerprint, b.fingerprint);
  });

  test('documents round-trip and skip broken records', () {
    final doc = SyncDocument({
      'k': _rec(3, 30),
      'gone': const SyncRecord(time: 40, data: {}, deleted: true),
    });
    final decoded = SyncDocument.decode(doc.encode());
    expect(decoded.records['k']!.fingerprint, _rec(3, 30).fingerprint);
    expect(decoded.records['gone']!.deleted, isTrue);

    final broken = SyncDocument.decode(
      '{"format":1,"records":{"ok":{"time":1,"data":{}},"bad":{"data":{}}}}',
    );
    expect(broken.records.keys, ['ok']);
    expect(() => SyncDocument.decode('[]'), throwsFormatException);
  });
}
