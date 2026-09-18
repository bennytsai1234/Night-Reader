import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:pointycastle/block/desede_engine.dart';
import 'package:pointycastle/export.dart' as pc;

import 'encode_utils_base.dart';
import 'encode_utils_base64.dart';

/// JsEncodeUtils 的對稱加密擴展
extension EncodeUtilsCrypto on EncodeUtilsBase {
  static dynamic symmetricCrypto(
    String action,
    String transformation,
    dynamic key,
    dynamic iv,
    dynamic data, {
    String outputFormat = 'base64',
  }) {
    final parts = transformation.split('/');
    final algorithmName = parts[0].toUpperCase();
    final modeName = parts.length > 1 ? parts[1].toUpperCase() : 'ECB';
    final keyBytes = EncodeUtilsBase.toBytes(key);
    final ivBytes = iv != null ? EncodeUtilsBase.toBytes(iv) : null;

    if (algorithmName == 'AES') {
      return _aesSymmetricCrypto(
        action,
        modeName,
        keyBytes,
        ivBytes,
        data,
        outputFormat,
      );
    } else {
      return _pointycastleSymmetricCrypto(
        action,
        algorithmName,
        modeName,
        keyBytes,
        ivBytes,
        data,
        outputFormat,
      );
    }
  }

  static dynamic _aesSymmetricCrypto(
    String action,
    String modeName,
    List<int> keyBytes,
    List<int>? ivBytes,
    dynamic data,
    String outputFormat,
  ) {
    final forEncryption = action == 'encrypt';
    final inputBytes =
        forEncryption
            ? Uint8List.fromList(EncodeUtilsBase.toBytes(data))
            : data is String
            ? base64.decode(data)
            : Uint8List.fromList(EncodeUtilsBase.toBytes(data));

    if (modeName != 'ECB' && ivBytes == null) {
      throw StateError('IV is required.');
    }

    final keyParameter = pc.KeyParameter(Uint8List.fromList(keyBytes));
    late final Uint8List resultBytes;

    if (modeName == 'GCM') {
      final cipher =
          pc.GCMBlockCipher(pc.AESEngine())
            ..reset()
            ..init(
              forEncryption,
              pc.AEADParameters(
                keyParameter,
                128,
                Uint8List.fromList(ivBytes!),
                Uint8List(0),
              ),
            );
      resultBytes = cipher.process(inputBytes);
    } else {
      final cipher =
          pc.PaddedBlockCipherImpl(
              pc.PKCS7Padding(),
              _createAesBlockCipher(modeName),
            )
            ..reset()
            ..init(
              forEncryption,
              pc.PaddedBlockCipherParameters(
                modeName == 'ECB'
                    ? keyParameter
                    : pc.ParametersWithIV(
                      keyParameter,
                      Uint8List.fromList(ivBytes!),
                    ),
                null,
              ),
            );
      resultBytes = cipher.process(inputBytes);
    }

    if (forEncryption) {
      return outputFormat == 'hex'
          ? hex.encode(resultBytes)
          : (outputFormat == 'bytes'
              ? resultBytes
              : base64.encode(resultBytes));
    }

    final decryptedBytes = Uint8List.fromList(resultBytes);
    return outputFormat == 'string'
        ? utf8.decode(decryptedBytes)
        : (outputFormat == 'bytes'
            ? decryptedBytes
            : (outputFormat == 'hex'
                ? hex.encode(decryptedBytes)
                : base64.encode(decryptedBytes)));
  }

  static pc.BlockCipher _createAesBlockCipher(String modeName) {
    final engine = pc.AESEngine();
    switch (modeName) {
      case 'CBC':
        return pc.CBCBlockCipher(engine);
      case 'CFB':
        return pc.CFBBlockCipher(engine, 8);
      case 'CTR':
        return pc.CTRBlockCipher(engine.blockSize, pc.CTRStreamCipher(engine));
      case 'ECB':
        return pc.ECBBlockCipher(engine);
      case 'OFB':
        return pc.OFBBlockCipher(engine, 8);
      default:
        return pc.SICBlockCipher(engine.blockSize, pc.SICStreamCipher(engine));
    }
  }

  static dynamic _pointycastleSymmetricCrypto(
    String action,
    String algorithmName,
    String modeName,
    List<int> keyBytes,
    List<int>? ivBytes,
    dynamic data,
    String outputFormat,
  ) {
    final engine = (algorithmName == 'DES') ? DESEngine() : DESedeEngine();
    final cipher = (modeName == 'ECB') ? engine : pc.CBCBlockCipher(engine);
    final padder = pc.PaddedBlockCipherImpl(pc.PKCS7Padding(), cipher)..init(
      action == 'encrypt',
      modeName == 'ECB'
          ? pc.PaddedBlockCipherParameters(
            pc.KeyParameter(Uint8List.fromList(keyBytes)),
            null,
          )
          : pc.PaddedBlockCipherParameters(
            pc.ParametersWithIV(
              pc.KeyParameter(Uint8List.fromList(keyBytes)),
              Uint8List.fromList(ivBytes ?? List.filled(engine.blockSize, 0)),
            ),
            null,
          ),
    );
    if (action == 'encrypt') {
      final encryptedBytes = padder.process(
        Uint8List.fromList(EncodeUtilsBase.toBytes(data)),
      );
      return outputFormat == 'hex'
          ? hex.encode(encryptedBytes)
          : (outputFormat == 'bytes'
              ? encryptedBytes
              : base64.encode(encryptedBytes));
    } else {
      final decryptedBytes = padder.process(
        data is String
            ? EncodeUtilsBase64.base64DecodeToBytes(data)
            : Uint8List.fromList(EncodeUtilsBase.toBytes(data)),
      );
      return outputFormat == 'string'
          ? utf8.decode(decryptedBytes)
          : (outputFormat == 'bytes'
              ? decryptedBytes
              : (outputFormat == 'hex'
                  ? hex.encode(decryptedBytes)
                  : base64.encode(decryptedBytes)));
    }
  }
}
