import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
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
      final k = Key(Uint8List.fromList(keyBytes));
      final v = ivBytes != null ? IV(Uint8List.fromList(ivBytes)) : null;
      final encrypter = Encrypter(AES(k, mode: _getAESMode(modeName)));
      if (action == 'encrypt') {
        final encrypted = encrypter.encryptBytes(
          EncodeUtilsBase.toBytes(data),
          iv: v,
        );
        return outputFormat == 'hex'
            ? hex.encode(encrypted.bytes)
            : (outputFormat == 'bytes' ? encrypted.bytes : encrypted.base64);
      } else {
        final decrypted = Uint8List.fromList(
          encrypter.decryptBytes(
            data is String
                ? Encrypted.fromBase64(data)
                : Encrypted(Uint8List.fromList(EncodeUtilsBase.toBytes(data))),
            iv: v,
          ),
        );
        return outputFormat == 'string'
            ? utf8.decode(decrypted)
            : (outputFormat == 'bytes'
                ? decrypted
                : (outputFormat == 'hex'
                    ? hex.encode(decrypted)
                    : base64.encode(decrypted)));
      }
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

  static AESMode _getAESMode(String mode) {
    switch (mode) {
      case 'CBC':
        return AESMode.cbc;
      case 'CFB':
        return AESMode.cfb64;
      case 'CTR':
        return AESMode.ctr;
      case 'ECB':
        return AESMode.ecb;
      case 'OFB':
        return AESMode.ofb64;
      case 'GCM':
        return AESMode.gcm;
      default:
        return AESMode.sic;
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
