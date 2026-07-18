import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

/// 段落級日文→中文翻譯介面。
///
/// 回傳 null 代表暫不可用（模型未就緒、平台錯誤、逾時），呼叫端應
/// 保留原文、不得擋住章節載入。
abstract class JapaneseParagraphTranslator {
  Future<String?> translate(String paragraph);
}

/// 翻譯模型狀態（設定列 subtitle 顯示用）。
enum JapaneseModelStatus { unknown, missing, downloading, ready, failed }

/// ML Kit on-device 日文→中文翻譯。
///
/// - 離線 NMT，模型（ja/zh 各約 30MB）首次啟用時下載一次，之後全離線。
/// - 輸出為簡體中文；繁簡調整由呼叫端沿用既有 [ChineseTextConverter]
///   後處理（見 reader_v2_japanese_pass.dart）。
/// - 平台通道只能在主 isolate 使用，不可搬進內容轉換 worker。
/// - 段落級 LRU 快取：同章重讀與 ±2 章預載大量重複命中。
class MlkitJapaneseTranslator implements JapaneseParagraphTranslator {
  MlkitJapaneseTranslator._();

  static final MlkitJapaneseTranslator instance = MlkitJapaneseTranslator._();

  static const int _cacheLimit = 512;

  /// 首段翻譯含模型載入，放寬逾時；之後逐段通常在數十 ms 內。
  static const Duration _translateTimeout = Duration(seconds: 12);

  final OnDeviceTranslatorModelManager _modelManager =
      OnDeviceTranslatorModelManager();
  final LinkedHashMap<String, String> _cache = LinkedHashMap();
  OnDeviceTranslator? _translator;
  bool _modelsReady = false;

  /// 模型狀態通知（設定頁 subtitle 綁定）。
  final ValueNotifier<JapaneseModelStatus> status =
      ValueNotifier<JapaneseModelStatus>(JapaneseModelStatus.unknown);

  Future<bool> areModelsDownloaded() async {
    try {
      final results = await Future.wait([
        _modelManager.isModelDownloaded(TranslateLanguage.japanese.bcpCode),
        _modelManager.isModelDownloaded(TranslateLanguage.chinese.bcpCode),
      ]);
      final ready = results.every((downloaded) => downloaded);
      _modelsReady = ready;
      if (status.value != JapaneseModelStatus.downloading) {
        status.value =
            ready ? JapaneseModelStatus.ready : JapaneseModelStatus.missing;
      }
      return ready;
    } catch (_) {
      return false;
    }
  }

  /// 下載 ja/zh 模型（預設要求 Wi-Fi）。開啟設定開關時呼叫。
  Future<bool> ensureModels({bool wifiRequired = true}) async {
    if (_modelsReady) return true;
    if (await areModelsDownloaded()) return true;
    status.value = JapaneseModelStatus.downloading;
    try {
      final results = await Future.wait([
        _modelManager.downloadModel(
          TranslateLanguage.japanese.bcpCode,
          isWifiRequired: wifiRequired,
        ),
        _modelManager.downloadModel(
          TranslateLanguage.chinese.bcpCode,
          isWifiRequired: wifiRequired,
        ),
      ]);
      final ready = results.every((downloaded) => downloaded);
      _modelsReady = ready;
      status.value =
          ready ? JapaneseModelStatus.ready : JapaneseModelStatus.failed;
      return ready;
    } catch (_) {
      status.value = JapaneseModelStatus.failed;
      return false;
    }
  }

  @override
  Future<String?> translate(String paragraph) async {
    if (paragraph.trim().isEmpty) return null;
    final cached = _cache.remove(paragraph);
    if (cached != null) {
      _cache[paragraph] = cached; // LRU touch
      return cached;
    }
    if (!_modelsReady && !await areModelsDownloaded()) return null;
    try {
      _translator ??= OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.japanese,
        targetLanguage: TranslateLanguage.chinese,
      );
      final translated = await _translator!
          .translateText(paragraph)
          .timeout(_translateTimeout);
      if (translated.trim().isEmpty) return null;
      _cache[paragraph] = translated;
      if (_cache.length > _cacheLimit) {
        _cache.remove(_cache.keys.first);
      }
      return translated;
    } catch (_) {
      return null;
    }
  }
}
