import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content_transformer.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';

Map<String, Object?> _args({Object? rules = const <Object?>[]}) =>
    <String, Object?>{
      'bookName': '測試書',
      'bookOrigin': 'local',
      'chapterTitle': '第一章',
      'rawContent': '第一段。\n第二段。',
      'rulesJson': rules,
      'useReplaceRules': true,
      'reSegmentEnabled': true,
      'chineseConvertType': 0,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final worker = ReaderV2ContentTransformWorker.instance;

  test('the worker processes chapter content off the main isolate', () async {
    final result = await worker.process(_args());

    expect(result['content'], '　　第一段。\n　　第二段。');
  });

  test('the worker also splits paragraphs and hashes the chapter', () async {
    final result = await worker.process({..._args(), 'chapterIndex': 7});

    final document = result['document']! as ReaderV2Content;
    final onMain = ReaderV2Content.fromRaw(
      chapterIndex: 7,
      title: '第一章',
      rawText: '　　第一段。\n　　第二段。',
    );
    expect(document.chapterIndex, 7);
    expect(document.paragraphs, onMain.paragraphs);
    expect(document.displayText, onMain.displayText);
    expect(document.contentHash, onMain.contentHash);
  });

  test(
    'a failed chapter surfaces as an error and the worker keeps serving',
    () async {
      await expectLater(
        worker.process(_args(rules: const <Object?>['不是規則'])),
        throwsA(isA<ReaderV2ContentTransformException>()),
      );

      final result = await worker.process(_args());
      expect(result['content'], '　　第一段。\n　　第二段。');
    },
  );
}
