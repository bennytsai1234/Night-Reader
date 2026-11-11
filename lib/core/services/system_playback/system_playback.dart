import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/core/services/app_log_service.dart';

import 'now_playing_artwork.dart';

/// 系統播放資訊上的一項內容：通知欄、鎖定畫面、各家「島」、藍牙耳機與車用
/// 螢幕看到的標題、副標與封面。
@immutable
class NowPlaying {
  const NowPlaying({
    required this.id,
    required this.title,
    required this.bookName,
    required this.author,
    this.coverSource,
    this.kind = BookSourceKind.novel,
    this.duration,
  });

  /// 這一項的識別碼，換章、換書時不同。
  final String id;

  /// 標題：章名。
  final String title;

  final String bookName;
  final String author;

  /// 書的封面來源（網址、`local://`、`file://`、`memory://`）；null 是畫
  /// 預設封面（夜空）。
  final String? coverSource;

  /// 這本書是哪一類：沒有封面時照它畫預設封面的變體。
  final BookSourceKind kind;

  /// 這一項的總長；不給（朗讀、還不知道長度）時系統不畫進度條。
  final Duration? duration;

  /// 副標：「書名 · 作者」，沒有作者時只有書名。
  String get subtitle {
    final name = author.trim();
    return name.isEmpty ? bookName : '$bookName · $name';
  }

  @override
  bool operator ==(Object other) =>
      other is NowPlaying &&
      other.id == id &&
      other.title == title &&
      other.bookName == bookName &&
      other.author == author &&
      other.coverSource == coverSource &&
      other.kind == kind &&
      other.duration == duration;

  @override
  int get hashCode =>
      Object.hash(id, title, bookName, author, coverSource, kind, duration);
}

/// 系統播放資訊上除了播放／暫停以外的按鈕。只宣告當下真的做得到的：系統照
/// 宣告畫按鈕，宣告了做不到的按鈕按下去不會有反應。
enum PlaybackControl {
  skipToPrevious,
  skipToNext,

  /// 倒退、快轉 [SystemPlayback.skipInterval]。
  rewind,
  fastForward,
  stop,

  /// 拖進度條。宣告時系統才畫可以拖的進度條。
  seek,
}

/// 正在播的一方（朗讀、有聲書播放器）：系統播放資訊的按鈕、耳機與藍牙的
/// 按鍵都送到它。
abstract interface class PlaybackOwner {
  void onPlay();

  /// 按了暫停，或另一方開始播、接手了系統播放資訊。
  void onPause();
  void onStop();
  void onSkipToNext();
  void onSkipToPrevious();
  void onRewind();
  void onFastForward();
  void onSeek(Duration position);
}

/// 系統播放資訊：App 的媒體工作階段（Android 的媒體通知與前景服務、iOS 的
/// 正在播放），整個 App 一份。
///
/// 一次只有一方在播：後開始播的接手，原本在播的那一方收到
/// [PlaybackOwner.onPause]（ADR 0055）。
class SystemPlayback {
  SystemPlayback({NowPlayingArtwork? artwork})
    : _artwork = artwork ?? NowPlayingArtwork();

  static final SystemPlayback instance = SystemPlayback();

  /// 倒退、快轉按鈕一次跳多少，和有聲書播放器的按鈕一致（ADR 0055）。
  static const Duration skipInterval = Duration(seconds: 10);

  /// 狀態列上的小圖示。和按鈕圖示一樣只用名字指定，發布版要在
  /// `android/app/src/main/res/raw/keep.xml` 留著。
  static const String notificationIcon = 'drawable/ic_stat_night_reader';

  final NowPlayingArtwork _artwork;
  _SessionHandler? _handler;
  Future<void>? _starting;
  PlaybackOwner? _owner;

  /// 最後交給系統的內容；開好工作階段時照它補上。
  _Shown? _shown;

  /// 上一次系統拒收的錯誤。
  String? _lastRejection;

  /// 系統拒收播放資訊：連續相同的錯誤只記第一次，每次播放、暫停、換章都
  /// 失敗時不會擠掉紀錄裡其他的錯誤。
  void _logRejection(Object error) {
    final text = '$error';
    if (text == _lastRejection) return;
    _lastRejection = text;
    AppLog.e(
      'SystemPlayback: system rejected playback info: $text',
      error: error,
    );
  }

  /// 向系統開媒體工作階段。開不起來時只少了系統播放資訊，播放照常；下次
  /// 呼叫再試。
  Future<void> start() {
    if (_handler != null) return Future<void>.value();
    return _starting ??= _start();
  }

  Future<void> _start() async {
    try {
      _handler = await AudioService.init(
        builder: () => _SessionHandler(this),
        config: const AudioServiceConfig(
          // 重要性只在頻道建立時給得了（低：不跳出、不出聲），之後被改成
          // 「重要」就改不回來。舊的頻道在使用者手機上被改成重要、每次更新
          // 都跳橫幅，換一個新的，舊的由 MainActivity 刪掉。
          androidNotificationChannelId: 'com.night_reader.playback',
          androidNotificationChannelName: '夜讀播放',
          // 狀態列只畫圖示的形狀：App 圖示整張不透明，會變成一塊白色方塊。
          androidNotificationIcon: notificationIcon,
          androidNotificationOngoing: true,
          // 封面原圖可能上千像素，整張送給系統會超過跨程序傳遞的上限。
          artDownscaleWidth: 512,
          artDownscaleHeight: 512,
          rewindInterval: skipInterval,
          fastForwardInterval: skipInterval,
        ),
      );
      // 播放狀態、標題送不進系統時，audio_service 只把錯誤放進這裡，不丟出來。
      AudioService.asyncError.listen(_logRejection);
      final shown = _shown;
      if (shown != null) _handler!.show(shown, _artwork);
    } catch (error) {
      AppLog.e(
        'SystemPlayback: AudioService.init failed (no system playback info): '
        '$error',
        error: error,
      );
    } finally {
      _starting = null;
    }
  }

  /// [owner] 正在播 [item]（[playing] 為 false 是暫停中）：把標題、副標、
  /// 封面與按鈕交給系統。內容和上一次一樣時不做事，可以每次狀態變動都呼叫。
  ///
  /// 有 [position] 時系統畫播到哪裡，之後照 [speed] 自己往前推，所以只在
  /// 播放、暫停、拖動、換倍速時交一次就好；[buffering] 是正在等資料。
  ///
  /// 不是目前那一方時，開始播才接手；暫停中的狀態不交，免得被接手後暫停時
  /// 又把系統播放資訊搶回去。
  void show(
    PlaybackOwner owner, {
    required NowPlaying item,
    required bool playing,
    required Set<PlaybackControl> controls,
    Duration? position,
    double speed = 1.0,
    bool buffering = false,
  }) {
    final previous = _owner;
    if (!identical(previous, owner)) {
      if (!playing) return;
      _owner = owner;
      previous?.onPause();
    }
    final shown = _Shown(
      item: item,
      playing: playing,
      controls: controls,
      position: position,
      speed: speed,
      buffering: buffering,
    );
    if (shown == _shown) return;
    _shown = shown;
    _handler?.show(shown, _artwork);
  }

  /// [owner] 不播了：還是它在播時收掉系統播放資訊（通知消失）。
  void release(PlaybackOwner owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _shown = null;
    _handler?.clear();
  }
}

@immutable
class _Shown {
  const _Shown({
    required this.item,
    required this.playing,
    required this.controls,
    required this.position,
    required this.speed,
    required this.buffering,
  });

  final NowPlaying item;
  final bool playing;
  final Set<PlaybackControl> controls;
  final Duration? position;
  final double speed;
  final bool buffering;

  @override
  bool operator ==(Object other) =>
      other is _Shown &&
      other.item == item &&
      other.playing == playing &&
      setEquals(other.controls, controls) &&
      other.position == position &&
      other.speed == speed &&
      other.buffering == buffering;

  @override
  int get hashCode => Object.hash(
    item,
    playing,
    Object.hashAllUnordered(controls),
    position,
    speed,
    buffering,
  );
}

class _SessionHandler extends BaseAudioHandler {
  _SessionHandler(this._playback);

  final SystemPlayback _playback;

  PlaybackOwner? get _owner => _playback._owner;

  /// 目前交給系統的那一項。
  NowPlaying? _item;

  void show(_Shown shown, NowPlayingArtwork artwork) {
    final item = shown.item;
    if (item != _item) {
      _item = item;
      // 同一本書換章時封面早就換好，和文字一起送出，不會閃一下沒有封面。
      final art = artwork.resolved(
        item.coverSource,
        item.bookName,
        kind: item.kind,
      );
      mediaItem.add(_mediaItemOf(item, art));
      if (art == null) {
        unawaited(
          artwork
              .resolve(item.coverSource, item.bookName, kind: item.kind)
              .then(
                (uri) {
                  if (_item != item) return;
                  mediaItem.add(_mediaItemOf(item, uri));
                },
                // 連預設封面都寫不出來（例如儲存空間滿了）：只是沒有封面。
                onError: (Object error) => AppLog.e(
                  'SystemPlayback: no artwork for ${item.bookName}: $error',
                  error: error,
                ),
              ),
        );
      }
    }
    playbackState.add(_stateOf(shown));
  }

  void clear() {
    _item = null;
    playbackState.add(
      PlaybackState(processingState: AudioProcessingState.idle),
    );
    mediaItem.add(null);
  }

  static MediaItem _mediaItemOf(NowPlaying item, Uri? art) => MediaItem(
    id: item.id,
    title: item.title,
    // Android 與 iOS 都把 artist 當副標顯示；藍牙與車用螢幕另外顯示 album。
    artist: item.subtitle,
    album: item.bookName,
    artUri: art,
    duration: item.duration,
  );

  static PlaybackState _stateOf(_Shown shown) {
    final controls = <MediaControl>[
      if (shown.controls.contains(PlaybackControl.skipToPrevious))
        MediaControl.skipToPrevious,
      if (shown.controls.contains(PlaybackControl.rewind)) MediaControl.rewind,
      shown.playing ? MediaControl.pause : MediaControl.play,
      if (shown.controls.contains(PlaybackControl.fastForward))
        MediaControl.fastForward,
      if (shown.controls.contains(PlaybackControl.skipToNext))
        MediaControl.skipToNext,
      if (shown.controls.contains(PlaybackControl.stop)) MediaControl.stop,
    ];
    // 收合的通知只放上一章、播放鍵、下一章；跳秒與停止在展開後才有。
    final expandedOnly = {
      MediaControl.rewind,
      MediaControl.fastForward,
      MediaControl.stop,
    };
    final compact = <int>[
      for (var i = 0; i < controls.length; i++)
        if (!expandedOnly.contains(controls[i])) i,
    ];
    return PlaybackState(
      controls: controls,
      androidCompactActionIndices: compact,
      systemActions: {
        MediaAction.playPause,
        if (shown.controls.contains(PlaybackControl.seek)) MediaAction.seek,
      },
      playing: shown.playing,
      processingState: shown.buffering
          ? AudioProcessingState.buffering
          : AudioProcessingState.ready,
      updatePosition: shown.position ?? Duration.zero,
      speed: shown.speed,
    );
  }

  /// 系統（通知、鎖定畫面、耳機、藍牙）按了 [command]：記一筆再交給目前
  /// 那一方。崩潰日誌與崩潰前紀錄看得到按了什麼、有沒有人接。
  PlaybackOwner? _received(String command) {
    final owner = _owner;
    AppLog.d('系統播放按了 $command（${owner?.runtimeType ?? '沒有人在播'}）');
    return owner;
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) {
    AppLog.d(
      '系統播放按了媒體鍵 ${button.name}（狀態：${playbackState.value.playing ? '播放中' : '暫停'}）',
    );
    return super.click(button);
  }

  @override
  Future<void> play() async => _received('播放')?.onPlay();

  @override
  Future<void> pause() async => _received('暫停')?.onPause();

  @override
  Future<void> stop() async => _received('停止')?.onStop();

  @override
  Future<void> skipToNext() async => _received('下一個')?.onSkipToNext();

  @override
  Future<void> skipToPrevious() async => _received('上一個')?.onSkipToPrevious();

  @override
  Future<void> rewind() async => _received('倒退')?.onRewind();

  @override
  Future<void> fastForward() async => _received('快轉')?.onFastForward();

  /// 拖動不記：拖一次系統可能連送好幾次，會把崩潰前紀錄的日誌擠掉。
  @override
  Future<void> seek(Duration position) async => _owner?.onSeek(position);
}
