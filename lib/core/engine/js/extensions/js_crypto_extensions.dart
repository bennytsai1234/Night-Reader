import 'dart:io' show gzip;
import 'dart:convert';
import 'package:convert/convert.dart';
import 'package:uuid/uuid.dart';
import '../js_extensions.dart';
import '../js_encode_utils.dart';

extension JsCryptoExtensions on JsExtensions {
  void injectCryptoExtensions() {
    // 實作 java.createSymmetricCrypto
    runtime.onMessage('symmetricCrypto', (dynamic args) {
      final payload = _decodeArgs(args);
      final action = payload[0].toString();
      final transformation = payload[1].toString();
      final key = payload[2];
      final iv = payload[3];
      final data = payload[4];
      final outputFormat = payload[5].toString();

      return JsEncodeUtils.symmetricCrypto(
        action,
        transformation,
        key,
        iv,
        data,
        outputFormat: outputFormat,
      );
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
      final payload = _decodeArgs(args);
      if (payload is List && payload.length >= 2) {
        final data = payload[0].toString();
        final algorithm = payload[1].toString();
        final hexFormat =
            payload.length > 2 ? payload[2].toString() != 'false' : true;
        return JsEncodeUtils.digest(data, algorithm, hexFormat: hexFormat);
      }
      return '';
    });
    runtime.onMessage('_hmacHex', (dynamic args) {
      final payload = _decodeArgs(args);
      if (payload is List && payload.length >= 3) {
        return JsEncodeUtils.hmacHex(
          payload[0].toString(),
          payload[1].toString(),
          payload[2].toString(),
        );
      }
      return '';
    });
    runtime.onMessage('_desEncodeToBase64String', (dynamic args) {
      final payload = _decodeArgs(args);
      if (payload is List && payload.length >= 2) {
        final data = payload[0];
        final key = payload[1];
        final transformation =
            payload.length > 2 &&
                    payload[2] != null &&
                    payload[2].toString().isNotEmpty
                ? payload[2].toString()
                : 'DES/ECB/PKCS5Padding';
        final iv = payload.length > 3 ? payload[3] : null;
        return JsEncodeUtils.symmetricCrypto(
          'encrypt',
          transformation,
          key,
          iv,
          data,
          outputFormat: 'base64',
        );
      }
      return '';
    });
    runtime.onMessage('_base64Encode', (dynamic args) {
      final payload = _decodeArgs(args);
      return JsEncodeUtils.base64Encode(payload);
    });
    runtime.onMessage('_base64Decode', (dynamic args) {
      final payload = _decodeArgs(args);
      final str = payload is List ? payload[0].toString() : payload.toString();
      final charset =
          payload is List && payload.length > 1
              ? payload[1].toString()
              : 'UTF-8';
      return JsEncodeUtils.base64Decode(str, charset: charset);
    });
    runtime.onMessage('_base64DecodeToBytes', (dynamic args) {
      final payload = _decodeArgs(args);
      final str =
          payload is List ? payload.first.toString() : payload.toString();
      return jsonEncode(JsEncodeUtils.base64DecodeToBytes(str).toList());
    });
    runtime.onMessage(
      '_hexEncode',
      (dynamic args) => hex.encode(utf8.encode(args.toString())),
    );
    runtime.onMessage(
      '_hexDecode',
      (dynamic args) => utf8.decode(hex.decode(args.toString())),
    );
    runtime.onMessage('_randomUUID', (dynamic args) => const Uuid().v4());
    runtime.onMessage('_gunzipBytes', (dynamic args) {
      final payload = _decodeArgs(args);
      final bytesSource =
          payload is List && payload.every((item) => item is num)
              ? payload
              : (payload is List ? payload.first : payload);
      final bytes = List<int>.from(bytesSource as List);
      return jsonEncode(gzip.decode(bytes));
    });
  }

  dynamic _decodeArgs(dynamic args) {
    if (args is String) {
      try {
        return jsonDecode(args);
      } catch (_) {
        return args;
      }
    }
    return args;
  }
}
