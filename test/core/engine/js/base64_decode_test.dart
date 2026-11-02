import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/js/js_encode_utils.dart';

/// Base64 解碼照 Legado：一個或兩個參數的 `base64Decode` 是 Hutool，
/// 有 flags 的與 `base64DecodeToByteArray` 是 `android.util.Base64.decode`。
/// 兩個都略過字母表以外的字元（完本小说网的密文裡有網頁 JSON 轉義留下的
/// `\/`）。
void main() {
  String text(List<int> bytes) => utf8.decode(bytes);

  group('android.util.Base64.decode（flags 有給）', () {
    test('字母表以外的字元略過：反斜線、空白、換行', () {
      // "hello?>>" 的 Base64 是 aGVsbG8/Pj4=；網頁 JSON 把 / 寫成 \/。
      expect(
        text(EncodeUtilsBase64.base64DecodeToBytes(r'aGVsbG8\/Pj4=', flags: 0)),
        'hello?>>',
      );
      expect(
        text(
          EncodeUtilsBase64.base64DecodeToBytes(
            'aGVs\r\nbG8/ Pj4=\n',
            flags: 0,
          ),
        ),
        'hello?>>',
      );
    });

    test('預設收 +/，URL_SAFE 收 -_，另一種字母表的字元略過', () {
      // 0xFB 0xFF 0xBE：標準 +/++ 之類；用 "??>" -> Pz8-
      expect(EncodeUtilsBase64.base64DecodeToBytes('Pz8-', flags: 8), [
        63,
        63,
        62,
      ]);
      expect(EncodeUtilsBase64.base64DecodeToBytes('Pz8+', flags: 0), [
        63,
        63,
        62,
      ]);
      // 預設模式下 '-' 不是字母表，略過，只剩 3 個字元：Pz8 -> 2 位元組。
      expect(EncodeUtilsBase64.base64DecodeToBytes('Pz8-', flags: 0), [63, 63]);
    });

    test('結尾可以不補 =，補了也行', () {
      expect(text(EncodeUtilsBase64.base64DecodeToBytes('YQ', flags: 0)), 'a');
      expect(
        text(EncodeUtilsBase64.base64DecodeToBytes('YQ==', flags: 0)),
        'a',
      );
      expect(
        text(EncodeUtilsBase64.base64DecodeToBytes('YWI', flags: 0)),
        'ab',
      );
    });

    test('Android 會丟錯的照丟：剩一個字元、= 後面還有字', () {
      expect(
        () => EncodeUtilsBase64.base64DecodeToBytes('YWJjZ', flags: 0),
        throwsFormatException,
      );
      expect(
        () => EncodeUtilsBase64.base64DecodeToBytes('YQ==YQ', flags: 0),
        throwsFormatException,
      );
      expect(
        () => EncodeUtilsBase64.base64DecodeToBytes('=YQ', flags: 0),
        throwsFormatException,
      );
    });
  });

  group('Hutool Base64.decode（沒給 flags）', () {
    test('字母表以外的字元略過，兩種字母表都收', () {
      expect(
        text(EncodeUtilsBase64.base64DecodeToBytes(r'aGVsbG8\/Pj4=')),
        'hello?>>',
      );
      expect(JsEncodeUtils.base64Decode('Pz8_'), '???');
      expect(JsEncodeUtils.base64Decode('Pz8/'), '???');
    });

    test('缺的 = 不用補，多出的一個字元丟掉', () {
      expect(JsEncodeUtils.base64Decode('YQ'), 'a');
      expect(JsEncodeUtils.base64Decode('YWJjZ'), 'abc');
      expect(JsEncodeUtils.base64Decode(''), '');
    });
  });
}
