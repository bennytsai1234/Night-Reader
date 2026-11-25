import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/local_book/local_book_service.dart';
import 'package:night_reader/core/local_book/txt_parser.dart';
import 'package:night_reader/core/utils/big5.dart';
import 'package:night_reader/core/utils/gb18030.dart';

/// 段落之間夠遠（Legado 挑規則時，相隔不到 1000 字的只算一處）。
String _body(String marker) => '　　$marker${'正文內容。' * 300}\n';

List<String> _titles(String content) => [
  for (final span in TxtParser.splitText(content)) span.title,
];

void main() {
  group('照 Legado 的內建目錄規則挑一條分章', () {
    test('序章、番外與「第 1 章」（中間有空白）都分得出', () {
      final content = [
        '序章\n${_body('a')}',
        '第 1 章 出發\n${_body('b')}',
        '第 2 章 到了\n${_body('c')}',
        '番外\n${_body('d')}',
      ].join();
      expect(_titles(content), ['序章', '第 1 章 出發', '第 2 章 到了', '番外']);
    });

    test('Chapter 1 這種英文章名', () {
      final content = [
        'Chapter 1 Start\n${_body('a')}',
        'Chapter 2 Middle\n${_body('b')}',
        'Chapter 3 End\n${_body('c')}',
      ].join();
      expect(_titles(content), [
        'Chapter 1 Start',
        'Chapter 2 Middle',
        'Chapter 3 End',
      ]);
    });

    test('「1、標題」這種數字加分隔符的章名', () {
      final content = [
        '1、開始\n${_body('a')}',
        '2、中間\n${_body('b')}',
        '3、結尾\n${_body('c')}',
      ].join();
      expect(_titles(content), ['1、開始', '2、中間', '3、結尾']);
    });

    test('「卷五 某某」這種卷、章在前的章名', () {
      final content = [
        '卷一 起\n${_body('a')}',
        '卷二 承\n${_body('b')}',
        '卷三 轉\n${_body('c')}',
      ].join();
      expect(_titles(content), ['卷一 起', '卷二 承', '卷三 轉']);
    });

    test('「第一节课」「第一回合」開頭的句子不當成章名', () {
      final content = [
        '第一章 开学\n${_body('a')}',
        '第一节课下课后，他走出教室。\n${_body('b')}',
        '第二章 比赛\n${_body('c')}',
        '第一回合结束，比分落后。\n${_body('d')}',
        '第三章 回家\n${_body('e')}',
      ].join();
      expect(_titles(content), ['第一章 开学', '第二章 比赛', '第三章 回家']);
    });

    test('「第一回」的古典小說照樣分得出', () {
      final content = [
        '第一回 灵根育孕源流出\n${_body('a')}',
        '第二回 悟彻菩提真妙理\n${_body('b')}',
        '第三回 四海千山皆拱伏\n${_body('c')}',
      ].join();
      expect(_titles(content), ['第一回 灵根育孕源流出', '第二回 悟彻菩提真妙理', '第三回 四海千山皆拱伏']);
    });

    test('以「第三章」開頭、超過 30 字的一整行不當成章名', () {
      final content = [
        '第一章 开始\n${_body('a')}',
        '第三章里讲到的那个人后来又出现了，他说自己从来没有离开过这座城市，大家都不信。\n',
        _body('b'),
        '第二章 结束\n${_body('c')}',
      ].join();
      expect(_titles(content), ['第一章 开始', '第二章 结束']);
    });

    test('一條規則都對不到時照長度切', () {
      final content = _body('a') * 200;
      expect(_titles(content).first, '正文 (1)');
    });
  });

  group('第一章前面的字', () {
    test('只有空白時不另立「前言」，併進第一章', () {
      final content = '\n\n第一章 开始\n${_body('a')}第二章 结束\n${_body('b')}';
      final spans = TxtParser.splitText(content);
      expect([for (final s in spans) s.title], ['第一章 开始', '第二章 结束']);
      expect(spans.first.start, 0);
    });

    test('有字時叫「前言」', () {
      final content = '书名\n作者：某某\n\n第一章 开始\n${_body('a')}第二章 结束\n${_body('b')}';
      expect(_titles(content).first, '前言');
    });
  });

  group('照長度切時切在換行', () {
    test('沒有章名時，每一塊都從一段的開頭開始', () {
      final paragraph = '${'字' * 997}。\n';
      final content = paragraph * 100;
      final spans = TxtParser.splitText(content);
      expect(spans.length, greaterThan(1));
      for (final span in spans.skip(1)) {
        expect(
          content[span.start - 1],
          '\n',
          reason: '「${span.title}」從一段的中間開始',
        );
      }
      expect(spans.last.end, content.length);
    });

    test('超長的一章再切時也切在換行', () {
      final paragraph = '${'字' * 997}。\n';
      final content = '第一章 很长\n${paragraph * 120}第二章 短\n${_body('a')}';
      final spans = TxtParser.splitText(content);
      final pieces = spans.where((s) => s.title.startsWith('第一章')).toList();
      expect(pieces.length, greaterThan(1));
      for (final span in pieces.skip(1)) {
        expect(content[span.start - 1], '\n');
      }
    });
  });

  group('分卷', () {
    test('章名後面直接接下一個章名的，標成分卷', () {
      final content = [
        '书名\n',
        '第一卷 起\n',
        '第一章 开始\n${_body('a')}',
        '第二章 继续\n${_body('b')}',
        '第二卷 承\n\n',
        '第三章 后来\n${_body('c')}',
      ].join();
      final spans = TxtParser.splitText(content);
      expect(
        {for (final s in spans) s.title: s.isVolume},
        {
          '前言': false,
          '第一卷 起': true,
          '第一章 开始': false,
          '第二章 继续': false,
          '第二卷 承': true,
          '第三章 后来': false,
        },
      );
    });

    test('匯入後分卷的章節記成分卷', () async {
      final dir = await Directory.systemTemp.createTemp('txt_volume_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/书.txt');
      await file.writeAsString(
        '书名\n第一卷 起\n第一章 开始\n${_body('a')}第二章 继续\n${_body('b')}',
      );
      final result = await LocalBookService().importBook(file.path);
      expect(
        [for (final c in result!.chapters) c.isVolume],
        [false, true, false, false],
      );
    });
  });

  group('從檔名取書名與作者（照 Legado）', () {
    Future<({String name, String author})> importNamed(String fileName) async {
      final dir = await Directory.systemTemp.createTemp('txt_name_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(utf8.encode('第一章 开始\n${_body('a')}'));
      final result = await LocalBookService().importBook(file.path);
      return (name: result!.book.name, author: result.book.author);
    }

    test('《書名》作者：某某', () async {
      expect(await importNamed('《斗破苍穹》作者：天蚕土豆.txt'), (
        name: '斗破苍穹',
        author: '天蚕土豆',
      ));
    });

    test('前後還有字的《書名》', () async {
      expect(await importNamed('[精校]《雪中悍刀行》烽火戏诸侯.txt'), (
        name: '雪中悍刀行',
        author: '[精校]烽火戏诸侯',
      ));
    });

    test('書名 作者：某某', () async {
      expect(await importNamed('凡人修仙传 作者：忘语.txt'), (
        name: '凡人修仙传',
        author: '忘语',
      ));
    });

    test('Title by Author', () async {
      expect(await importNamed('The Hobbit by Tolkien.txt'), (
        name: 'The Hobbit',
        author: 'Tolkien',
      ));
    });

    test('拆不出作者時書名是檔名、作者照舊寫「本地」', () async {
      expect(await importNamed('西游记.txt'), (name: '西游记', author: '本地'));
    });
  });

  test('Big5 的 TXT 認得出編碼，章名與正文都不是亂碼（L5）', () async {
    final dir = await Directory.systemTemp.createTemp('txt_big5_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/書.txt');
    String body(String marker) => '　　$marker他說：「我們走吧。」她點了點頭，沒有說話。\n' * 40;
    await file.writeAsBytes(
      Big5.encode('第一章 開始\n${body('甲')}第二章 結束\n${body('乙')}'),
    );
    final service = LocalBookService();
    final result = (await service.importBook(file.path))!;
    expect(result.book.charset, 'Big5');
    expect(result.chapters.map((c) => c.title), ['第一章 開始', '第二章 結束']);
    final content = await service.getContent(result.book, result.chapters[1]);
    expect(content, contains('乙他說：「我們走吧。」'));
  });

  test('Big5 的 TXT 有表裡沒有的字（造字）時，後面的章照樣從對的地方讀', () async {
    final dir = await Directory.systemTemp.createTemp('txt_big5_pua_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/書.txt');
    String body(String marker) => '　　$marker他說：「我們走吧。」她點了點頭，沒有說話。\n' * 40;
    await file.writeAsBytes([
      ...Big5.encode('第一章 開始\n${body('甲')}'),
      0xC7, 0xFD, 0x0A, // 造字區一格，解成替代字元
      ...Big5.encode('第二章 結束\n${body('乙')}'),
    ]);
    final service = LocalBookService();
    final result = (await service.importBook(file.path))!;
    expect(result.book.charset, 'Big5');
    final content = await service.getContent(result.book, result.chapters[1]);
    expect(content, startsWith('第二章 結束'));
  });

  // GB18030 的 TXT 有 GBK 沒有的字（emoji、擴充區漢字）時是四位元組，照
  // Legado 認成 GB18030；分章照四位元組數，後面的章從對的地方讀。
  test('GB18030 的 TXT 有四位元組的字時，章名與正文不是亂碼、分章位置對', () async {
    final dir = await Directory.systemTemp.createTemp('txt_gb18030_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/書.txt');
    String body(String marker) =>
        '　　$marker他笑了😀，走向𠀀村，价格¥5。她点了点头，没有说话。\n' * 40;
    await file.writeAsBytes(
      Gb18030.encode('第一章 开始\n${body('甲')}第二章 结束\n${body('乙')}'),
    );
    final service = LocalBookService();
    final result = (await service.importBook(file.path))!;
    expect(result.book.charset, 'GB18030');
    expect(result.chapters.map((c) => c.title), ['第一章 开始', '第二章 结束']);
    final content = await service.getContent(result.book, result.chapters[1]);
    expect(content, startsWith('第二章 结束'));
    expect(content, contains('乙他笑了😀，走向𠀀村，价格¥5。'));
  });
}
