import 'dart:math';
import 'dart:io' show ZLibDecoder, gzip;
import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:uuid/uuid.dart';

import '../js_extensions.dart';
import '../js_encode_utils.dart';

extension JsCryptoExtensions on JsExtensions {
  void injectCryptoExtensions() {
    // 實作 java.createSymmetricCrypto
    runtime.onMessage('symmetricCrypto', (dynamic args) {
      final payload = args;
      final action = payload[0].toString();
      final transformation = payload[1].toString();
      final key = payload[2];
      final iv = payload[3];
      final data = payload[4];
      final outputFormat = payload[5].toString();
      final charset = payload.length > 6 && payload[6] != null
          ? payload[6].toString()
          : 'UTF-8';
      final tagBits = payload.length > 7 && payload[7] is num
          ? (payload[7] as num).toInt()
          : 128;

      final result = EncodeUtilsCrypto.symmetricCrypto(
        action,
        transformation,
        key,
        iv,
        data,
        outputFormat: outputFormat,
        charset: charset,
        tagBits: tagBits,
      );
      // 位元組陣列直接傳回 JS 會變成空陣列，和其他傳位元組的橋接一樣改傳
      // JSON，由 JS 端的 normalizeByteArray 轉回陣列。
      return result is List<int> ? jsonEncode(result.toList()) : result;
    });

    // 加密沒給 IV、沒給金鑰時照 Java／Hutool 用隨機的。
    runtime.onMessage('_randomBytes', (dynamic args) {
      final random = Random.secure();
      final count = args is num ? args.toInt() : int.parse(args.toString());
      return jsonEncode(List.generate(count, (_) => random.nextInt(256)));
    });

    runtime.onMessage('rsaGenerateKeyPair', (dynamic args) {
      final pair = EncodeUtilsRsa.generateKeyPair(
        args is num ? args.toInt() : 1024,
      );
      return jsonEncode({
        'publicKey': pair.publicKey.toList(),
        'privateKey': pair.privateKey.toList(),
      });
    });

    // 注入輔助函式
    runtime.onMessage(
      '_md5Encode',
      (dynamic args) => JsEncodeUtils.md5Encode(args.toString()),
    );
    runtime.onMessage(
      '_md5Encode16',
      (dynamic args) => JsEncodeUtils.md5Encode16(args.toString()),
    );
    runtime.onMessage('_digest', (dynamic args) {
      final payload = args;
      if (payload is List && payload.length >= 2) {
        final data = payload[0].toString();
        final algorithm = payload[1].toString();
        final hexFormat = payload.length > 2
            ? payload[2].toString() != 'false'
            : true;
        return JsEncodeUtils.digest(data, algorithm, hexFormat: hexFormat);
      }
      return '';
    });
    runtime.onMessage('_hmacHex', (dynamic args) {
      final payload = args;
      if (payload is List && payload.length >= 3) {
        return JsEncodeUtils.hmacHex(
          payload[0].toString(),
          payload[1].toString(),
          payload[2].toString(),
        );
      }
      return '';
    });
    // java.createAsymmetricCrypto：[轉換, 加密?, 用公鑰?, 公鑰, 私鑰, 資料, 輸出]
    runtime.onMessage('asymmetricCrypto', (dynamic args) {
      final payload = args as List;
      final bytes = EncodeUtilsRsa.process(
        transformation: payload[0].toString(),
        encrypt: payload[1] == true,
        usePublicKey: payload[2] != false,
        publicKey: payload[3],
        privateKey: payload[4],
        data: payload[5],
      );
      return switch (payload[6].toString()) {
        'string' => utf8.decode(bytes, allowMalformed: true),
        'hex' => hex.encode(bytes),
        'base64' => base64.encode(bytes),
        _ => jsonEncode(bytes.toList()),
      };
    });

    // java.createSign：[演算法, 'sign' 或 'verify', 公鑰, 私鑰, 資料, 簽章, 輸出]
    runtime.onMessage('rsaSign', (dynamic args) {
      final payload = args as List;
      final algorithm = payload[0].toString();
      if (payload[1] == 'verify') {
        return EncodeUtilsRsa.verify(
          algorithm,
          payload[2],
          payload[4],
          payload[5],
        );
      }
      final bytes = EncodeUtilsRsa.sign(algorithm, payload[3], payload[4]);
      return switch (payload[6].toString()) {
        'hex' => hex.encode(bytes),
        'base64' => base64.encode(bytes),
        _ => jsonEncode(bytes.toList()),
      };
    });

    runtime.onMessage('_hmacBase64', (dynamic args) {
      final payload = args;
      if (payload is List && payload.length >= 3) {
        return EncodeUtilsHash.hmacBase64(
          payload[0].toString(),
          payload[1].toString(),
          payload[2].toString(),
        );
      }
      return '';
    });
    // java.base64Encode(data[, flags])、base64Decode(str[, charset 或 flags])、
    // base64DecodeToByteArray(str[, flags])：JS 送 {d: 資料, f: flags, c: 字元
    // 編碼}；flags 照 Android Base64，編碼預設 NO_WRAP、解碼預設 DEFAULT。
    runtime.onMessage('_base64Encode', (dynamic args) {
      final (data, flags, _) = _base64Args(args);
      return JsEncodeUtils.base64Encode(
        data,
        flags: flags ?? EncodeUtilsBase.base64NoWrap,
      );
    });
    runtime.onMessage('_base64Decode', (dynamic args) {
      final (data, flags, charset) = _base64Args(args);
      return JsEncodeUtils.base64Decode(
        data.toString(),
        charset: charset ?? 'UTF-8',
        flags: flags ?? 0,
      );
    });
    runtime.onMessage('_base64DecodeToBytes', (dynamic args) {
      final (data, flags, _) = _base64Args(args);
      return jsonEncode(
        JsEncodeUtils.base64DecodeToBytes(
          data.toString(),
          flags: flags ?? 0,
        ).toList(),
      );
    });
    runtime.onMessage(
      '_hexEncode',
      (dynamic args) => hex.encode(utf8.encode(args.toString())),
    );
    runtime.onMessage(
      '_hexDecode',
      (dynamic args) => utf8.decode(hex.decode(args.toString())),
    );
    runtime.onMessage(
      '_hexDecodeToBytes',
      (dynamic args) => jsonEncode(hex.decode(args.toString())),
    );
    runtime.onMessage('_randomUUID', (dynamic args) => const Uuid().v4());
    // java.security.MessageDigest：位元組進、位元組出。
    runtime.onMessage('_digestBytes', (dynamic args) {
      final payload = args as List;
      return jsonEncode(
        EncodeUtilsHash.digestBytes(
          List<int>.from(payload[0] as List),
          payload[1].toString(),
        ).toList(),
      );
    });
    // javax.crypto.Mac：[資料, 演算法（HmacSHA256 這類）, 金鑰]，都是位元組。
    runtime.onMessage('_hmacBytes', (dynamic args) {
      final payload = args as List;
      return jsonEncode(
        EncodeUtilsHash.hmacBytes(
          List<int>.from(payload[0] as List),
          payload[1].toString(),
          List<int>.from(payload[2] as List),
        ).toList(),
      );
    });
    // java.security.SecureRandom：n 個隨機位元組。
    runtime.onMessage('_randomBytes', (dynamic args) {
      final random = Random.secure();
      final count = args is num ? args.toInt() : int.tryParse('$args') ?? 0;
      return jsonEncode([for (var i = 0; i < count; i++) random.nextInt(256)]);
    });
    // java.util.zip.Inflater／InflaterInputStream：zlib，nowrap 時是沒有
    // 標頭的 deflate。
    runtime.onMessage('_inflateBytes', (dynamic args) {
      final payload = args as List;
      final bytes = List<int>.from(payload[0] as List);
      final raw = payload.length > 1 && payload[1] == true;
      return jsonEncode(ZLibDecoder(raw: raw).convert(bytes));
    });
    runtime.onMessage('_gunzipBytes', (dynamic args) {
      final payload = args;
      final bytesSource =
          payload is List && payload.every((item) => item is num)
          ? payload
          : (payload is List ? payload.first : payload);
      final bytes = List<int>.from(bytesSource as List);
      return jsonEncode(gzip.decode(bytes));
    });
  }
}

/// base64 呼叫的 `{d, f, c}`：資料、Android Base64 flags、字元編碼。
(dynamic, int?, String?) _base64Args(dynamic args) {
  if (args is! Map) return (args, null, null);
  final flags = args['f'];
  final charset = args['c'];
  return (args['d'], flags is num ? flags.toInt() : null, charset?.toString());
}
