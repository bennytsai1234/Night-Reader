import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../services/app_log_service.dart';
import '../services/http_client.dart';
import '../storage/app_storage_paths.dart';
import 'app_font.dart';

/// 一套字型目前的狀態。
sealed class FontStatus {
  const FontStatus();
}

/// 還沒下載。
final class FontMissing extends FontStatus {
  const FontMissing();
}

/// 下載中；[progress] 是 0–1。
final class FontDownloading extends FontStatus {
  const FontDownloading(this.progress);
  final double progress;
}

/// 已下載並註冊，可以用。
final class FontReady extends FontStatus {
  const FontReady();
}

/// 下載或載入失敗；可以再試。
final class FontFailed extends FontStatus {
  const FontFailed();
}

/// 下載、核對並註冊 [AppFont] 的字型檔（ADR 0045）。
///
/// 檔案放在支援資料夾的 `fonts/`，先寫成 `.part`，大小與 SHA-256 都對才改成
/// 正式檔名，所以正式檔存在就代表完整。註冊（`FontLoader`）一套只做一次；
/// 每次有字型變成可用，[changes] 通知一次，用到字型的地方（主題、閱讀設定）
/// 聽它重建或重排。
class FontLibrary {
  FontLibrary({
    this._dio,
    Future<Directory> Function()? directoryLoader,
    Future<void> Function(String family, Uint8List bytes)? register,
    @visibleForTesting AppFontFile? Function(AppFont font)? fileOf,
  }) : _directoryLoader = directoryLoader ?? _defaultDirectory,
       _register = register ?? _registerFont,
       _fileOf = fileOf ?? ((font) => font.file);

  /// App 共用的那一份。
  static FontLibrary instance = FontLibrary();

  final Dio? _dio;
  final Future<Directory> Function() _directoryLoader;
  final Future<void> Function(String family, Uint8List bytes) _register;
  final AppFontFile? Function(AppFont font) _fileOf;

  final Map<AppFont, ValueNotifier<FontStatus>> _status = {};
  final Map<AppFont, Future<bool>> _pending = {};
  final ValueNotifier<int> _changes = ValueNotifier(0);

  /// 有字型變成可用時通知。
  Listenable get changes => _changes;

  ValueListenable<FontStatus> status(AppFont font) => _notifier(font);

  ValueNotifier<FontStatus> _notifier(AppFont font) => _status.putIfAbsent(
    font,
    () => ValueNotifier(
      _fileOf(font) == null ? const FontReady() : const FontMissing(),
    ),
  );

  /// [font] 已經註冊、可以用時的字族名稱；系統字型或還不能用時是 null。
  String? familyOf(AppFont font) {
    final file = _fileOf(font);
    if (file == null) return null;
    return _notifier(font).value is FontReady ? file.family : null;
  }

  /// 開 App 時呼叫：選了的字型已經下載過就載入（等它好，第一幀就是這套
  /// 字）；還沒下載的在背景下載，好了再換上。
  Future<void> start(Iterable<AppFont> selected) async {
    final wanted = {
      for (final font in selected)
        if (_fileOf(font) != null) font,
    };
    final loads = <Future<void>>[];
    for (final font in wanted) {
      final file = await _fileFor(font);
      if (await _isComplete(file, _fileOf(font)!)) {
        loads.add(ensure(font).then((_) {}));
      } else {
        unawaited(ensure(font));
      }
    }
    await Future.wait(loads);
  }

  /// 讓 [font] 可以用：沒下載就下載、核對，再註冊。回傳是否可以用。同一套
  /// 同時被要求時共用同一次下載。
  Future<bool> ensure(AppFont font) {
    final spec = _fileOf(font);
    if (spec == null) return Future.value(true);
    if (_notifier(font).value is FontReady) return Future.value(true);
    return _pending.putIfAbsent(font, () async {
      try {
        final file = await _fileFor(font);
        if (!await _isComplete(file, spec)) await _download(font, spec, file);
        final bytes = await file.readAsBytes();
        await _register(spec.family, bytes);
        _notifier(font).value = const FontReady();
        _changes.value++;
        return true;
      } catch (error, stack) {
        AppLog.e(
          '字型 ${font.label} 下載或載入失敗: $error',
          error: error,
          stackTrace: stack,
        );
        _notifier(font).value = const FontFailed();
        return false;
      } finally {
        unawaited(Future.microtask(() => _pending.remove(font)));
      }
    });
  }

  Future<void> _download(AppFont font, AppFontFile spec, File file) async {
    final status = _notifier(font)..value = const FontDownloading(0);
    await file.parent.create(recursive: true);
    final partial = File('${file.path}.part');
    try {
      await (_dio ?? HttpClient().client).download(
        spec.url,
        partial.path,
        onReceiveProgress: (received, total) {
          final size = total > 0 ? total : spec.bytes;
          status.value = FontDownloading((received / size).clamp(0.0, 1.0));
        },
      );
      if (await partial.length() != spec.bytes ||
          await _sha256(partial.path) != spec.sha256) {
        throw StateError('${spec.fileName} 下載的內容和預期的不同');
      }
      await partial.rename(file.path);
    } finally {
      if (await partial.exists()) await partial.delete();
    }
  }

  Future<File> _fileFor(AppFont font) async =>
      File(p.join((await _directoryLoader()).path, _fileOf(font)!.fileName));

  /// 正式檔只在核對過後才改名出現，所以存在且大小對就是完整的。
  static Future<bool> _isComplete(File file, AppFontFile spec) async =>
      await file.exists() && await file.length() == spec.bytes;

  /// 十幾 MB 的雜湊放到背景算，不佔畫面的執行緒。
  static Future<String> _sha256(String path) => Isolate.run(
    () => sha256.convert(File(path).readAsBytesSync()).toString(),
  );

  static Future<Directory> _defaultDirectory() async =>
      Directory(p.join((await AppStoragePaths.supportDir()).path, 'fonts'));

  static Future<void> _registerFont(String family, Uint8List bytes) =>
      (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
}
