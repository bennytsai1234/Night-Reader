import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
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
      other.coverSource == coverSource;

  @override
  int get hashCode => Object.hash(id, title, bookName, author, coverSource);
}

/// 系統播放資訊上除了播放／暫停以外的按鈕。只宣告當下真的做得到的：系統照
/// 宣告畫按鈕，宣告了做不到的按鈕按下去不會有反應。
enum PlaybackControl {
  skipToPrevious,
  skipToNext,
  stop,

  /// 拖進度條。宣告時系統才畫可以拖的進度條。
  seek,
}

/// 正在播的一方（朗讀、有聲書播放器）：系統播放資訊的按鈕、耳機與藍牙的
/// 按鍵都送到它。
abstract interface class PlaybackOwner {
  void onPlay();
  void onPause();

  /// 按了停止，或另一方開始播、接手了系統播放資訊。
  void onStop();
  void onSkipToNext();
  void onSkipToPrevious();
  void onSeek(Duration position);
}

/// 系統播放資訊：App 的媒體工作階段（Android 的媒體通知與前景服務、iOS 的
/// 正在播放），整個 App 一份。
///
/// 一次只有一方在播：最後一個呼叫 [show] 的那一方接手，原本那一方收到
/// [PlaybackOwner.onStop]。
class SystemPlayback {
  SystemPlayback({NowPlayingArtwork? artwork})
    : _artwork = artwork ?? NowPlayingArtwork();

  static final SystemPlayback instance = SystemPlayback();

  final NowPlayingArtwork _artwork;
  _SessionHandler? _handler;
  Future<void>? _starting;
  PlaybackOwner? _owner;

  /// 最後交給系統的內容；開好工作階段時照它補上。
  _Shown? _shown;

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
          androidNotificationChannelId: 'com.night_reader.tts',
          androidNotificationChannelName: '夜讀朗讀',
          // 狀態列只畫圖示的形狀：App 圖示整張不透明，會變成一塊白色方塊。
          androidNotificationIcon: 'drawable/ic_stat_night_reader',
          androidNotificationOngoing: true,
          // 封面原圖可能上千像素，整張送給系統會超過跨程序傳遞的上限。
          artDownscaleWidth: 512,
          artDownscaleHeight: 512,
        ),
      );
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
  void show(
    PlaybackOwner owner, {
    required NowPlaying item,
    required bool playing,
    required Set<PlaybackControl> controls,
  }) {
    final previous = _owner;
    _owner = owner;
    if (previous != null && !identical(previous, owner)) previous.onStop();
    final shown = _Shown(item: item, playing: playing, controls: controls);
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
  });

  final NowPlaying item;
  final bool playing;
  final Set<PlaybackControl> controls;

  @override
  bool operator ==(Object other) =>
      other is _Shown &&
      other.item == item &&
      other.playing == playing &&
      setEquals(other.controls, controls);

  @override
  int get hashCode =>
      Object.hash(item, playing, Object.hashAllUnordered(controls));
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
      final art = artwork.resolved(item.coverSource, item.bookName);
      mediaItem.add(_mediaItemOf(item, art));
      if (art == null) {
        unawaited(
          artwork.resolve(item.coverSource, item.bookName).then((uri) {
            if (_item != item) return;
            mediaItem.add(_mediaItemOf(item, uri));
          }),
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
  );

  static PlaybackState _stateOf(_Shown shown) {
    final controls = <MediaControl>[
      if (shown.controls.contains(PlaybackControl.skipToPrevious))
        MediaControl.skipToPrevious,
      shown.playing ? MediaControl.pause : MediaControl.play,
      if (shown.controls.contains(PlaybackControl.skipToNext))
        MediaControl.skipToNext,
      if (shown.controls.contains(PlaybackControl.stop)) MediaControl.stop,
    ];
    // 收合的通知只放上一章、播放鍵、下一章，停止在展開後才有。
    final compact = <int>[
      for (var i = 0; i < controls.length; i++)
        if (controls[i] != MediaControl.stop) i,
    ];
    return PlaybackState(
      controls: controls,
      androidCompactActionIndices: compact,
      systemActions: {
        MediaAction.playPause,
        if (shown.controls.contains(PlaybackControl.seek)) MediaAction.seek,
      },
      playing: shown.playing,
      processingState: AudioProcessingState.ready,
    );
  }

  @override
  Future<void> play() async => _owner?.onPlay();

  @override
  Future<void> pause() async => _owner?.onPause();

  @override
  Future<void> stop() async => _owner?.onStop();

  @override
  Future<void> skipToNext() async => _owner?.onSkipToNext();

  @override
  Future<void> skipToPrevious() async => _owner?.onSkipToPrevious();

  @override
  Future<void> seek(Duration position) async => _owner?.onSeek(position);
}
