import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/js/js_encode_utils.dart';

// Fixed vectors cross-checked against Java 17 SunJCE, independently of the
// production encrypt/PointyCastle implementation.
void _expectSymmetricCryptoVector({
  required String transformation,
  required String key,
  required String? iv,
  required String expectedBase64,
  required String expectedHex,
}) {
  const data = 'Secret Message';

  expect(
    JsEncodeUtils.symmetricCrypto('encrypt', transformation, key, iv, data),
    expectedBase64,
  );
  expect(
    JsEncodeUtils.symmetricCrypto(
      'encrypt',
      transformation,
      key,
      iv,
      data,
      outputFormat: 'hex',
    ),
    expectedHex,
  );
  expect(
    JsEncodeUtils.symmetricCrypto(
      'decrypt',
      transformation,
      key,
      iv,
      expectedBase64,
      outputFormat: 'string',
    ),
    data,
  );
}

void main() {
  group('JsEncodeUtils Tests', () {
    test('MD5 encoding', () {
      expect(
        JsEncodeUtils.md5Encode('123456'),
        'e10adc3949ba59abbe56e057f20f883e',
      );
      expect(JsEncodeUtils.md5Encode16('123456'), '49ba59abbe56e057');
    });

    test('Base64 encoding/decoding', () {
      const original = 'Hello Legado';
      final encoded = JsEncodeUtils.base64Encode(original);
      expect(encoded, 'SGVsbG8gTGVnYWRv');
      expect(JsEncodeUtils.base64Decode(encoded), original);
    });

    test('AES Encryption/Decryption (CBC)', () {
      const key = '1234567890123456'; // 16 bytes
      const iv = '1234567890123456'; // 16 bytes

      _expectSymmetricCryptoVector(
        transformation: 'AES/CBC/PKCS7Padding',
        key: key,
        iv: iv,
        expectedBase64: 'CMHlJ2C+hBCPvr3PBJ8Ttg==',
        expectedHex: '08c1e52760be84108fbebdcf049f13b6',
      );
    });

    test('AES Encryption/Decryption (ECB)', () {
      _expectSymmetricCryptoVector(
        transformation: 'AES/ECB/PKCS7Padding',
        key: '1234567890123456',
        iv: null,
        expectedBase64: 'ehHEztsz2M0FZJu0wQrCVA==',
        expectedHex: '7a11c4cedb33d8cd05649bb4c10ac254',
      );
    });

    test('AES Encryption/Decryption (CTR and SIC)', () {
      for (final mode in ['CTR', 'SIC']) {
        _expectSymmetricCryptoVector(
          transformation: 'AES/$mode/PKCS7Padding',
          key: '1234567890123456',
          iv: '1234567890123456',
          expectedBase64: 'JhmufrkosKe+nZ+XX7gCAg==',
          expectedHex: '2619ae7eb928b0a7be9d9f975fb80202',
        );
      }
    });

    test('AES Encryption/Decryption (CFB64)', () {
      _expectSymmetricCryptoVector(
        transformation: 'AES/CFB/PKCS7Padding',
        key: '1234567890123456',
        iv: '1234567890123456',
        expectedBase64: 'JhmufrkosKfSASel8lp75w==',
        expectedHex: '2619ae7eb928b0a7d20127a5f25a7be7',
      );
    });

    test('AES Encryption/Decryption (OFB64)', () {
      _expectSymmetricCryptoVector(
        transformation: 'AES/OFB/PKCS7Padding',
        key: '1234567890123456',
        iv: '1234567890123456',
        expectedBase64: 'JhmufrkosKe627Rw8lXQ4g==',
        expectedHex: '2619ae7eb928b0a7badbb470f255d0e2',
      );
    });

    test('AES Encryption/Decryption (GCM)', () {
      _expectSymmetricCryptoVector(
        transformation: 'AES/GCM/NoPadding',
        key: '1234567890123456',
        iv: '1234567890123456',
        expectedBase64: '1cGGzuIZm4rxF8pQ5t+/WI4e1RWjl/uIItKvq16S',
        expectedHex:
            'd5c186cee2199b8af117ca50e6dfbf588e1ed515a397fb8822d2afab5e92',
      );
    });

    test('Digest algorithms', () {
      expect(
        JsEncodeUtils.digest('test', 'SHA-1'),
        'a94a8fe5ccb19ba61c4c0873d391e987982fbbd3',
      );
    });

    test('DES Encryption/Decryption (ECB)', () {
      const key = '12345678'; // 8 bytes for DES

      _expectSymmetricCryptoVector(
        transformation: 'DES/ECB/PKCS7Padding',
        key: key,
        iv: null,
        expectedBase64: 'd5/XhOQW1YHde796Xk09/Q==',
        expectedHex: '779fd784e416d581dd7bbf7a5e4d3dfd',
      );
    });

    test('3DES Encryption/Decryption (CBC)', () {
      const key = '123456789012345612345678'; // 24 bytes for 3DES
      const iv = '12345678'; // 8 bytes for 3DES CBC

      _expectSymmetricCryptoVector(
        transformation: 'DESede/CBC/PKCS7Padding',
        key: key,
        iv: iv,
        expectedBase64: '8RKZbp73cd1MQW8CAOsUvw==',
        expectedHex: 'f112996e9ef771dd4c416f0200eb14bf',
      );
    });

    test('HMAC generation', () {
      expect(
        JsEncodeUtils.hmacHex('hello', 'HmacMD5', 'key'),
        '04130747afca4d79e32e87cf2104f087',
      );
      expect(
        JsEncodeUtils.hmacHex('hello', 'HmacSHA256', 'key'),
        '9307b3b915efb5171ff14d8cb55fbcc798c6c0ef1456d66ded1a6aa723a58b7b',
      );
    });
  });
}
