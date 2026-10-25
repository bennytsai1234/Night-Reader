import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/js/js_encode_utils.dart';

// 對照答案由 Python cryptography（OpenSSL）與 openssl 命令列算出，和 Java
// 的 Cipher 一致。
const _plain = '夜讀 Night Reader 第一章：山雨欲來';
const _key16 = '0123456789abcdef';
const _iv16 = 'fedcba9876543210';

String _encrypt(String transformation, {String key = _key16, String? iv}) =>
    EncodeUtilsCrypto.symmetricCrypto(
      'encrypt',
      transformation,
      key,
      iv,
      _plain,
    ) as String;

String _decrypt(
  String transformation,
  String data, {
  String key = _key16,
  String? iv,
}) => EncodeUtilsCrypto.symmetricCrypto(
  'decrypt',
  transformation,
  key,
  iv,
  data,
  outputFormat: 'string',
) as String;

void main() {
  final vectors = {
    'AES/CBC/PKCS5Padding':
        'nRmiA4tZ9RKopqLxKpPmO18Bciqi8K22kaHQ23wdE9KeHjBn8HnHegQ5vh6k7lT4',
    'AES/CBC/PKCS7Padding':
        'nRmiA4tZ9RKopqLxKpPmO18Bciqi8K22kaHQ23wdE9KeHjBn8HnHegQ5vh6k7lT4',
    'AES/CBC/ZeroPadding':
        'nRmiA4tZ9RKopqLxKpPmO18Bciqi8K22kaHQ23wdE9JbvVC40VUDqg1PAkdgw4KX',
    'AES/CFB/NoPadding':
        '7u9KmVjwX0fRX6ui6k4PXGEaJMzNaPVlAmjJRpQJQIvT+CgC65evs1/es08=',
    'AES/CFB8/NoPadding':
        '7pASGxaWCnFkKdbhG5vOYLeQ6yZ7uGXIBLPYGc+NhZhoaWhGhZEKZ52XCGk=',
    'AES/OFB/NoPadding':
        '7u9KmVjwX0fRX6ui6k4PXCzhUmOY1ogAGhlVzb5HQnn++pYYXa8w2vP8suY=',
    'AES/CTR/NoPadding':
        '7u9KmVjwX0fRX6ui6k4PXCYAnhlICyFrXni2HRJmy7thC0One5mZ0v21LRI=',
  };

  for (final MapEntry(key: transformation, value: expected)
      in vectors.entries) {
    test('$transformation matches Java', () {
      expect(_encrypt(transformation, iv: _iv16), expected);
      expect(_decrypt(transformation, expected, iv: _iv16), _plain);
    });
  }

  test('AES with only the algorithm name is ECB with PKCS5 padding', () {
    const expected =
        'hTznUfNnxyITwF+6HsD8V2bj1aVMMra24y4ofdSqXjzl13/GDxCDaUnDIClow782';
    expect(_encrypt('AES'), expected);
    expect(_encrypt('AES/ECB/PKCS5Padding'), expected);
    expect(_decrypt('AES', expected), _plain);
  });

  test('AES GCM appends the tag like Java', () {
    const expected =
        'q7d+JZBPKEkl9GcQz/XRsp/ZAePailm09xbk/18tWKpwzeRG/kVCyqc5hYhFv4XEUCT46YfJT/Il7yOD';
    expect(_encrypt('AES/GCM/NoPadding', iv: _iv16.substring(0, 12)), expected);
    expect(
      _decrypt('AES/GCM/NoPadding', expected, iv: _iv16.substring(0, 12)),
      _plain,
    );
  });

  test('DES and 3DES match Java', () {
    expect(
      _encrypt('DES/CBC/PKCS5Padding', key: 'KW8Dvm2N', iv: '1ae2c94b'),
      '/cZzRiYlG40iaRiX4qgtDl8iO3A4TSrnqpRlvj3nIFiR+ZRjsL+ZZagC/yUNrNqo',
    );
    const triple =
        'AWZH676WJU1IwCwkL1g3Lngc/0+N94zXR9LT2zIDrLv+I3lqvuaWfbwYsT8kIj36';
    expect(
      _encrypt(
        'DESede/CBC/PKCS5Padding',
        key: 'OW84U8Eerdb99rtsTXWSILDO',
        iv: 'SK8bncVu',
      ),
      triple,
    );
    expect(
      _decrypt(
        'DESede/CBC/PKCS5Padding',
        triple,
        key: 'OW84U8Eerdb99rtsTXWSILDO',
        iv: 'SK8bncVu',
      ),
      _plain,
    );
  });

  test('ciphertext may be hex or URL-safe Base64 without padding', () {
    const hexText =
        '9d19a2038b59f512a8a6a2f12a93e63b5f01722aa2f0adb691a1d0db7c1d13d2'
        '9e1e3067f079c77a0439be1ea4ee54f8';
    expect(_decrypt('AES/CBC/PKCS5Padding', hexText, iv: _iv16), _plain);

    final urlSafe = base64Url.encode(hex.decode(hexText)).replaceAll('=', '');
    expect(_decrypt('AES/CBC/PKCS5Padding', urlSafe, iv: _iv16), _plain);
  });

  test('a wrong key says the padding is wrong instead of crashing', () {
    expect(
      () => _decrypt(
        'AES/CBC/PKCS5Padding',
        'nRmiA4tZ9RKopqLxKpPmO18Bciqi8K22kaHQ23wdE9KeHjBn8HnHegQ5vh6k7lT4',
        key: 'ffffffffffffffff',
        iv: _iv16,
      ),
      throwsA(predicate((Object e) => e.toString().contains('填充不對'))),
    );
  });

  test('digests and HMAC accept Java names', () {
    expect(
      EncodeUtilsHash.digest(_plain, 'SHA-512'),
      '14cae8ee4de99ad64071d2e891fafab6ed95783aa7ee53bfb7d82afd186e49e3'
      '999091c35c6805f1582d7d05af577daa3bfb16ffa8c7629c39ef057842146de6',
    );
    expect(
      EncodeUtilsHash.digest(_plain, 'sha384', hexFormat: false),
      'XGoj3CTMPm+m+O9DAr4Fc3jGYBlkVxHosF/2Upi8raFPqhnDZtw3BjuF+qQwR0kC',
    );
    expect(
      EncodeUtilsHash.digest(_plain, 'SHA3-256'),
      'b1a4333f39f7bd2bb6844861e5dbd4effc1d142933c98de11048ee6fcb04416c',
    );
    expect(
      EncodeUtilsHash.hmacHex(_plain, 'HmacSHA256', _key16),
      'e18cb902b671c7194d4739e5e6f70e763f3d2ed13972d607baf8e7d43585142b',
    );
    expect(
      EncodeUtilsHash.hmacBase64(_plain, 'HMAC-SHA1', _key16),
      'RcIthmJ4naPxIEkdIjawBlLrfws=',
    );
    expect(
      EncodeUtilsHash.hmacHex(_plain, 'HmacSHA512', _key16),
      'edb63520b2e977309687c68d4401ef36f63d12b2091438ad5e87e04b697bf460'
      '67a5f0ffa88a36b2392a2848bae49f408147ff1cc058cfe3765cbbc810fe247a',
    );
    expect(JsEncodeUtils.md5Encode('abc'), '900150983cd24fb0d6963f7d28e17f72');
  });
}
