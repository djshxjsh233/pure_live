import 'dart:async';
import 'package:rxdart/rxdart.dart';
import '../models/player_state.dart';
import '../models/player_exception.dart';
import '../models/player_error_type.dart';
import 'package:pure_live/common/index.dart';
import '../interface/unified_player_interface.dart';
import 'package:video_player/video_player.dart';

/// 官方媒体内核适配器（安卓 = Media3/ExoPlayer，与抖音/B站等同类）
/// 优点：系统原生音频链 → 系统音效/多扬声器/低音炮全开、音量正常
/// 缺点：部分非主流 FLV 兼容性可能不如 MPV；失败时由 EngineFallbackManager 回落到 mpv
class VideoPlayerAdapter implements UnifiedPlayer {
  VideoPlayerController? _controller;

  bool _initialized = false;
  bool _disposed = false;

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
  // init
  // =========================
  @override
  Future<void> init() async {
    if (_initialized) return;
    _disposed = false;
    _currentUrl = null;
    _stateSubject.add(PlayerState.initializing);
    try {
      // video_player 无预建播放器，初始化即“就绪”（播放器在 setDataSource 时创建）
      _initialized = true;
      _stateSubject.add(PlayerState.initialized);
    } catch (e, s) {
      final exception = PlayerException(
        message: 'VideoPlayerAdapter init failed',
        type: PlayerErrorType.initialization,
        error: e,
        stackTrace: s,
      );
      _safeAddError(exception);
      _stateSubject.add(PlayerState.error);
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

    // 换源：销毁旧 controller 重建（video_player 官方机制）
    await _destroyController();
    _currentUrl = url;

    _loadingSubject.add(true);
    _stateSubject.add(PlayerState.preparing);
    _completeSubject.add(false);
    _widthSubject.add(null);
    _heightSubject.add(null);

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: headers.isEmpty ? null : headers,
      );
      _controller = controller;
      controller.addListener(_onControllerEvent);
      await controller.initialize();

      // 设置音量（尊重房间保存音量/全局静音）
      final targetVolume = room?.getSavedVolume() ?? 1.0;
      await controller.setVolume(targetVolume.clamp(0.0, 1.0));

      _stateSubject.add(PlayerState.ready);
      if (controller.value.isPlaying) {
        _stateSubject.add(PlayerState.playing);
      }
      await controller.play();
    } catch (e, s) {
      final exception = PlayerException(
        message: 'VideoPlayer open failed',
        type: PlayerErrorType.source,
        error: e,
        stackTrace: s,
      );
      _safeAddError(exception);
      _stateSubject.add(PlayerState.error);
      throw exception;
    } finally {
      _loadingSubject.add(false);
    }
  }

  // =========================
  // controller events
  // =========================
  void _onControllerEvent() {
    if (_disposed) return;
    final c = _controller;
    if (c == null) return;
    final v = c.value;

    _playingSubject.add(v.isPlaying);

    if (v.hasError) {
      final exception = PlayerException(
        message: v.errorDescription ?? 'VideoPlayer error',
        type: PlayerErrorType.native,
      );
      _safeAddError(exception);
      _stateSubject.add(PlayerState.error);
      return;
    }

    if (v.isBuffering) {
      _loadingSubject.add(true);
      _stateSubject.add(PlayerState.buffering);
    } else {
      _loadingSubject.add(false);
    }

    if (v.size.width > 0 && v.size.height > 0) {
      _widthSubject.add(v.size.width.toInt());
      _heightSubject.add(v.size.height.toInt());
    }

    // 直播流 isLive 无完成后；非直播播完触发
    if (!v.isPlaying && !v.isBuffering && v.duration != Duration.zero && v.position >= v.duration) {
      _completeSubject.add(true);
      _stateSubject.add(PlayerState.completed);
    }
  }

  // =========================
  // controls
  // =========================
  @override
  Future<void> play() async {
    await _controller?.play();
  }

  @override
  Future<void> pause() async {
    await _controller?.pause();
  }

  @override
  Future<void> stop() async {
    await _controller?.pause();
    _stateSubject.add(PlayerState.stopped);
  }

  @override
  Future<void> softStop() async {
    await _controller?.pause();
  }

  @override
  Future<void> setVolume(double volume) async {
    await _controller?.setVolume(volume.clamp(0.0, 1.0));
  }

  @override
  Future<void> setHardwareDecode(bool enabled) async {
    // Media3 不支持运行时切换硬软解（系统自动选择），no-op
  }

  // =========================
  // widget
  // =========================
  @override
  Widget getVideoWidget() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return Container(color: Colors.black);
    }
    final ratio = c.value.aspectRatio;
    if (ratio <= 0 || ratio.isNaN || ratio.isInfinite) {
      return Container(color: Colors.black, child: Center(child: VideoPlayer(c)));
    }
    return Container(
      color: Colors.black,
      child: Center(child: AspectRatio(aspectRatio: ratio, child: VideoPlayer(c))),
    );
  }

  // =========================
  // dispose
  // =========================
  Future<void> _destroyController() async {
    final c = _controller;
    _controller = null;
    if (c != null) {
      c.removeListener(_onControllerEvent);
      try {
        await c.dispose();
      } catch (_) {}
    }
  }

  @override
  Future<void> hardDispose() async {
    if (_disposed) return;
    _disposed = true;
    _initialized = false;
    await _destroyController();
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
  // getters
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

  void _safeAddError(PlayerException exception) {
    if (_disposed) return;
    if (_errorSubject.isClosed) return;
    _currentUrl = null;
    _errorSubject.add(exception);
  }
}