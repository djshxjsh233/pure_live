import 'dart:async';
import 'package:rxdart/rxdart.dart';
import '../models/player_state.dart';
import '../models/player_exception.dart';
import '../models/player_error_type.dart';
import 'package:pure_live/common/index.dart';
import '../interface/unified_player_interface.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:pure_live/common/global/platform_utils.dart';

class MediaKitAdapter implements UnifiedPlayer {
  late Player _player;

  late final VideoController _controller;

  bool _initialized = false;

  bool _disposed = false;

  bool _listenerBound = false;

  String? _currentUrl;

  // =========================
  // subjects
  // =========================

  final _stateSubject = BehaviorSubject<PlayerState>.seeded(PlayerState.idle);

  final _playingSubject = BehaviorSubject<bool>.seeded(false);

  final _loadingSubject = BehaviorSubject<bool>.seeded(false);

  final _errorSubject = PublishSubject<PlayerException>();

  final _completeSubject = BehaviorSubject<bool>.seeded(false);

  final _widthSubject = BehaviorSubject<int?>.seeded(null);

  final _heightSubject = BehaviorSubject<int?>.seeded(null);

  // =========================
  // subscriptions
  // =========================

  final List<StreamSubscription> _subscriptions = [];

  // =========================
  // init
  // =========================

  @override
  Future<void> init() async {
    if (_initialized) return;

    _disposed = false;

    _listenerBound = false;

    _currentUrl = null;

    try {
      _stateSubject.add(PlayerState.initializing);

      _player = Player();

      if (_player.platform is NativePlayer) {
        final native = _player.platform as dynamic;

        await native.setProperty('force-seekable', 'yes');

        await native.setProperty('protocol_whitelist', 'httpproxy,udp,rtp,tcp,tls,data,file,http,https,crypto');

        await native.setProperty('demuxer-lavf-probsize', '2097152');

        await native.setProperty('demuxer-lavf-analyzeduration', '10');

        // ★ 直播流畅 / 网络优化 (仅网络流生效, 提高缓存抗抖动)
        await native.setProperty('stream-live-override', 'yes');
        await native.setProperty('cache', 'yes');
        await native.setProperty('cache-secs', '30');
        await native.setProperty('cache-pause-initial', 'yes');
        await native.setProperty('cache-pause', 'yes');
        await native.setProperty('demuxer-readahead-secs', '30');
        await native.setProperty('network-timeout', '30');

        if (SettingsService.to.player.customPlayerOutput.v) {
          await native.setProperty('ao', SettingsService.to.player.audioOutputDriver.v);
        }

        if (SettingsService.to.proxy.enableProxy.v && SettingsService.to.proxy.proxyHost.v.isNotEmpty) {
          final proxyUrl = "http://${SettingsService.to.proxy.proxyHost.v}:${SettingsService.to.proxy.proxyPort.v}";

          await native.setProperty('http-proxy', proxyUrl);
        }

        if (PlatformUtils.isMacOS) {
          await native.setProperty('hwdec', 'no');
        }
      }

      // =========================
      // controller
      // =========================
      _controller = SettingsService.to.player.playerCompatMode.v
          ? VideoController(
              _player,
              configuration: const VideoControllerConfiguration(vo: 'mediacodec_embed', hwdec: 'mediacodec'),
            )
          : SettingsService.to.player.customPlayerOutput.v
          ? VideoController(
              _player,
              configuration: VideoControllerConfiguration(
                vo: SettingsService.to.player.videoOutputDriver.v,
                hwdec: PlatformUtils.isMacOS ? 'no' : SettingsService.to.player.videoHardwareDecoder.v,
                enableHardwareAcceleration: !PlatformUtils.isMacOS,
              ),
            )
          : VideoController(
              _player,
              configuration: VideoControllerConfiguration(
                enableHardwareAcceleration: PlatformUtils.isMacOS ? false : SettingsService.to.player.enableCodec.v,
                hwdec: PlatformUtils.isMacOS ? 'no' : null,
                androidAttachSurfaceAfterVideoParameters: false,
              ),
            );

      // 下发底层 MPV 内核配置
      await _bindListeners();

      _initialized = true;

      _stateSubject.add(PlayerState.initialized);
    } catch (e, s) {
      final exception = PlayerException(
        message: 'MediaKit init failed',
        type: PlayerErrorType.initialization,
        error: e,
        stackTrace: s,
      );

      _safeAddError(exception);

      throw exception;
    }
  }

  // =========================
  // datasource
  // =========================

  @override
  Future<void> setDataSource(
    String url,
    List<String> playUrls,
    Map<String, String> headers, {
    LiveRoom? room,
  }) async {
    if (_disposed) return;

    if (_currentUrl == url && isPlayingNow) {
      return;
    }
    _currentUrl = url;

    try {
      _loadingSubject.add(true);

      _stateSubject.add(PlayerState.preparing);

      _completeSubject.add(false);

      _widthSubject.add(null);

      _heightSubject.add(null);

      await _player.open(Media(url, httpHeaders: headers), play: true);

      _stateSubject.add(PlayerState.ready);

      if (PlatformUtils.isMobile) {
        await setVolume(1.0);
      } else {
        final targetVolume = room?.getSavedVolume() ?? 1.0;
        await setVolume(targetVolume);
      }
    } catch (e, s) {
      final exception = PlayerException(
        message: 'Media open failed',
        type: PlayerErrorType.source,
        error: e,
        stackTrace: s,
      );

      _safeAddError(exception);

      _stateSubject.add(PlayerState.error);

      throw exception;
    } finally {
      if (!_disposed) {
        _loadingSubject.add(false);
      }
    }
  }

  // =========================
  // listeners
  // =========================

  Future<void> _bindListeners() async {
    if (_listenerBound) return;

    _listenerBound = true;

    await _cancelAllSubscriptions();

    // =========================
    // playing
    // =========================

    _subscriptions.add(
      _player.stream.playing.listen(
        (playing) {
          if (_disposed) return;

          _playingSubject.add(playing);

          if (!_loadingSubject.value) {
            _stateSubject.add(playing ? PlayerState.playing : PlayerState.paused);
          }
        },
        onError: (e, s) {
          _emitError(e, s, PlayerErrorType.native);
        },
      ),
    );

    // =========================
    // buffering
    // =========================

    _subscriptions.add(
      _player.stream.buffering.listen(
        (loading) {
          if (_disposed) return;

          _loadingSubject.add(loading);

          if (loading) {
            _stateSubject.add(PlayerState.buffering);
          } else {
            _stateSubject.add(_playingSubject.value ? PlayerState.playing : PlayerState.paused);
          }
        },
        onError: (e, s) {
          _emitError(e, s, PlayerErrorType.native);
        },
      ),
    );

    // =========================
    // width
    // =========================

    _subscriptions.add(
      _player.stream.width.listen((val) {
        if (_disposed) return;

        _widthSubject.add(val);
      }),
    );

    // =========================
    // height
    // =========================

    _subscriptions.add(
      _player.stream.height.listen((val) {
        if (_disposed) return;

        _heightSubject.add(val);
      }),
    );

    // =========================
    // completed
    // =========================

    _subscriptions.add(
      _player.stream.completed.listen(
        (completed) {
          if (_disposed) return;

          if (!completed) return;

          _completeSubject.add(true);

          _stateSubject.add(PlayerState.completed);
        },
        onError: (e, s) {
          _emitError(e, s, PlayerErrorType.native);
        },
      ),
    );

    // =========================
    // error
    // =========================

    _subscriptions.add(
      _player.stream.error.distinct().listen((error) {
        if (_disposed) return;

        final type = _mapErrorType(error.toString());

        _safeAddError(PlayerException(message: error.toString(), type: type));

        _stateSubject.add(PlayerState.error);
      }),
    );
  }

  // =========================
  // cancel subscriptions
  // =========================

  Future<void> _cancelAllSubscriptions() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }

    _subscriptions.clear();
  }

  // =========================
  // emit error
  // =========================

  void _emitError(Object error, StackTrace stackTrace, PlayerErrorType type) {
    if (_disposed) return;

    _safeAddError(PlayerException(message: error.toString(), type: type, error: error, stackTrace: stackTrace));

    _stateSubject.add(PlayerState.error);
  }

  void _safeAddError(PlayerException exception) {
    if (_disposed) return;

    if (_errorSubject.isClosed) return;

    _errorSubject.add(exception);
  }

  // =========================
  // error type
  // =========================

  PlayerErrorType _mapErrorType(String error) {
    final lower = error.toLowerCase();

    if (lower.contains('network') || lower.contains('timeout') || lower.contains('io')) {
      return PlayerErrorType.network;
    }

    if (lower.contains('codec') || lower.contains('mediacodec') || lower.contains('decode')) {
      return PlayerErrorType.codec;
    }

    if (lower.contains('404') || lower.contains('source') || lower.contains('open')) {
      return PlayerErrorType.source;
    }

    if (lower.contains('surface') || lower.contains('texture')) {
      return PlayerErrorType.texture;
    }

    return PlayerErrorType.native;
  }

  // =========================
  // widget
  // =========================

  @override
  Widget getVideoWidget() {
    return RepaintBoundary(
      child: Video(
        controller: _controller,
        controls: NoVideoControls,
        pauseUponEnteringBackgroundMode: !SettingsService.to.app.enableBackgroundPlay.v,
        resumeUponEnteringForegroundMode: !SettingsService.to.app.enableBackgroundPlay.v,
      ),
    );
  }

  // =========================
  // play
  // =========================

  @override
  Future<void> play() async {
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    await _player.pause();

    await _player.seek(Duration.zero);

    _stateSubject.add(PlayerState.stopped);
  }

  @override
  Future<void> softStop() async {
    await _player.setVolume(0.0);

    await _player.pause();
  }

  @override
  Future<void> setVolume(double volume) async {
    final vol = (volume * 100).clamp(0.0, 100.0);

    await _player.setVolume(vol);
  }

  // =========================
  // dispose
  // =========================

  @override
  Future<void> hardDispose() async {
    if (_disposed) return;

    _disposed = true;

    _initialized = false;

    _listenerBound = false;

    await _cancelAllSubscriptions();

    try {
      await _player.stop();
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 300));

    try {
      await _player.dispose();
    } catch (_) {}

    await Future.wait([
      _stateSubject.close(),
      _playingSubject.close(),
      _loadingSubject.close(),
      _errorSubject.close(),
      _completeSubject.close(),
      _widthSubject.close(),
      _heightSubject.close(),
    ]);
  }

  // =========================
  // getter
  // =========================

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isPlayingNow => _playingSubject.value;

  @override
  bool get isReusable => false;

  @override
  Stream<PlayerState> get onStateChanged => _stateSubject.stream;

  @override
  Stream<bool> get onPlaying => _playingSubject.stream;

  @override
  Stream<PlayerException> get onError => _errorSubject.stream;

  @override
  Stream<bool> get onLoading => _loadingSubject.stream;

  @override
  Stream<bool> get onComplete => _completeSubject.stream;

  @override
  Stream<int?> get width => _widthSubject.stream;

  @override
  Stream<int?> get height => _heightSubject.stream;
}
