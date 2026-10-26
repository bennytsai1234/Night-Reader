import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/utils/string_utils.dart';
import 'package:night_reader/features/search/widgets/search_result_item.dart';

/// 書源給的字數與分類各寫各的；卡片上要統一寫法，不把日期當成字數或分類。
void main() {
  group('wordCountFormat', () {
    test('各種寫法統一成萬字、千字、字', () {
      expect(StringUtils.wordCountFormat('1234567'), '123.5萬字');
      expect(StringUtils.wordCountFormat('123.4K'), '12.3萬字');
      expect(StringUtils.wordCountFormat('56.8万字'), '56.8萬字');
      expect(StringUtils.wordCountFormat('字数：1.2M'), '120萬字');
      expect(StringUtils.wordCountFormat('3,456,789字'), '345.7萬字');
      expect(StringUtils.wordCountFormat('１２３４５字'), '1.2萬字');
      expect(StringUtils.wordCountFormat('50w'), '50萬字');
      expect(StringUtils.wordCountFormat('3500'), '3.5千字');
      expect(StringUtils.wordCountFormat('3000'), '3千字');
      expect(StringUtils.wordCountFormat('850'), '850字');
      expect(StringUtils.wordCountFormat(12000), '1.2萬字');
    });

    test('四捨五入後滿十千就寫成萬', () {
      expect(StringUtils.wordCountFormat('9949'), '9.9千字');
      expect(StringUtils.wordCountFormat('9999'), '1萬字');
    });

    test('一位小數照十進位四捨五入，不受浮點誤差影響', () {
      expect(StringUtils.wordCountFormat('11499'), '1.1萬字');
      expect(StringUtils.wordCountFormat('11500'), '1.2萬字');
      expect(StringUtils.wordCountFormat('14500'), '1.5萬字');
      expect(StringUtils.wordCountFormat('1450'), '1.5千字');
    });

    test('格式化過的結果再格式化一次不變', () {
      for (final value in ['123.5萬字', '1萬字', '3.5千字', '850字']) {
        expect(StringUtils.wordCountFormat(value), value);
      }
      expect(StringUtils.wordCountFormat('100.0萬字'), '100萬字');
    });

    test('讀不出字數或是日期時不顯示', () {
      expect(StringUtils.wordCountFormat(null), '');
      expect(StringUtils.wordCountFormat(''), '');
      expect(StringUtils.wordCountFormat('0'), '');
      expect(StringUtils.wordCountFormat('未知'), '');
      expect(StringUtils.wordCountFormat('2024-05-01'), '');
      expect(StringUtils.wordCountFormat('更新于3天前'), '');
      expect(StringUtils.wordCountFormat('2024 年 10 月 15 日'), '');
      expect(StringUtils.wordCountFormat('共850章'), '');
      expect(StringUtils.wordCountFormat('12.3 萬字'), '12.3萬字');
      expect(StringUtils.wordCountFormat('约50万+'), '50萬字');
    });

    test('一長串數字不是字數，不顯示也不出錯', () {
      expect(StringUtils.wordCountFormat('9' * 400), '');
      expect(StringUtils.wordCountFormat('9' * 20), '');
      expect(StringUtils.wordCountFormat(double.infinity), '');
      expect(StringUtils.wordCountFormat(double.nan), '');
    });
  });

  group('kindLabels', () {
    test('丟掉日期、更新時間與數字，留下分類', () {
      expect(StringUtils.kindLabels('玄幻,连载,2024-05-01 12:30,123.4万字,3天前'), [
        '玄幻',
        '连载',
      ]);
      expect(StringUtils.kindLabels('都市｜生活、都市'), ['都市', '生活']);
      expect(StringUtils.kindLabels('12.3万'), isEmpty);
      expect(StringUtils.kindLabels(null), isEmpty);
    });

    test('千分位、單位前的空白與「3 小時前」不會被拆成殘片', () {
      expect(StringUtils.kindLabels('玄幻,1,234,567字'), ['玄幻']);
      expect(StringUtils.kindLabels('玄幻,12.3 萬字'), ['玄幻']);
      expect(StringUtils.kindLabels('玄幻,3 小時前'), ['玄幻']);
    });

    test('含數字的分類照留', () {
      expect(StringUtils.kindLabels('玄幻,3D文字冒險'), ['玄幻', '3D文字冒險']);
    });
  });

  group('displayWordCount', () {
    test('字數欄沒有時從分類裡寫成「…字」的標籤補', () {
      expect(StringUtils.displayWordCount(null, '玄幻,字数：88万'), '88萬字');
      expect(StringUtils.displayWordCount('', '玄幻,12.3万'), '');
      expect(StringUtils.displayWordCount('5000', '玄幻,88万字'), '5千字');
      expect(StringUtils.displayWordCount(null, '玄幻,1,234,567字'), '123.5萬字');
      expect(StringUtils.displayWordCount(null, '玄幻,字數：1,234,567字'), '123.5萬字');
      expect(StringUtils.displayWordCount('', '玄幻,12.3 萬字'), '12.3萬字');
      expect(StringUtils.displayWordCount(null, '玄幻,3D文字冒險'), '');
    });
  });

  group('formatSearchResultMetadata', () {
    test('作者 · 字數 · 分類', () {
      expect(
        formatSearchResultMetadata(
          author: '愛潛水的烏賊',
          kind: '玄幻,2024-05-01',
          wordCount: '4456789',
        ),
        '愛潛水的烏賊 · 445.7萬字 · 玄幻',
      );
      expect(formatSearchResultMetadata(kind: '2024-05-01'), '資訊未提供');
    });
  });
}
