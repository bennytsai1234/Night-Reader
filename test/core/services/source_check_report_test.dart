import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/check_source_service.dart';

void main() {
  test('a check stopped before any source finished still has a report', () {
    const report = SourceCheckReport(<SourceCheckEntry>[], plannedCount: 3);
    expect(report.stopped, isTrue);
    expect(report.isPresent, isTrue);
    expect(report.summary, startsWith('已停止，校驗了 0/3 個：'));
  });

  test('a check that ran to the end does not say stopped', () {
    expect(SourceCheckReport.empty.stopped, isFalse);
    expect(SourceCheckReport.empty.isPresent, isFalse);
    expect(SourceCheckReport.empty.summary, startsWith('可用 0'));
  });
}
