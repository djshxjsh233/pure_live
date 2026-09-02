import 'dart:io';
import 'dart:async';
import 'dart:developer';
import 'player_pool.dart';
import 'line_fallback_manager.dart';
import '../models/player_state.dart';
import '../models/player_engine.dart';
import 'engine_fallback_manager.dart';
import 'package:floating/floating.dart';
import '../models/player_exception.dart';
import 'package:remixicon/remixicon.dart';
import '../models/player_error_type.dart';
import 'package:rxdart/rxdart.dart' hide Rx;
import 'package:pure_live/common/index.dart';
import '../interface/unified_player_interface.dart';
import 'package:pure_live/routes/app_navigation.dart';
import 'package:pure_live/player/utils/fullscreen.dart';
import 'package:flutter_floating/flutter_floating.dart';
import 'package:pure_live/player/utils/player_consts.dart';
import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/player/utils/pip_window_widget.dart';
import 'package:pure_live/modules/live_play/player_state.dart';
import 'package:pure_live/player/core/live_audio_service.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';

class PlayerManager {
  final PlayerPool playerPool;
  final EngineFallbackManager fallbackManager;
  final LineFallbackManager lineManager;
  /// 所有线路/引擎都失败时回调：由上层重新获取流地址（如抖音播放URL失效刷新）
  Future<void> Function()? onRefreshUrls;
  int _refreshUrlsCount = 0;

  int _sessionId = 0;
  bool _isClosing = false;

  PlayerManager({
    required this.playerPool,
    required this.fallbackManager,
    required this.lineManager,
  }) {
    isInPip.listen((value) {
      GlobalPlayerState.to.isPipMode.value = value;
    });
  }

  bool _isSessionValid(int id) => !_disposed && !_isClosing && _sessionId == id;

  UnifiedPlayer? _currentPlayer;
  PlayerEngine? _runtimeEngine;
  PlayerEngine? _defaultEngine;

  String? _currentUrl;
  List<String> _currentPlayUrls = [];
  Map<String, String> _currentHeaders = {};

  final RxBool isInitialized = false.obs;
  final RxBool hasError = false.obs;
  final RxBool isVerticalVideo = false.obs;
  final RxBool isInPip = false.obs;
  final RxBool isFloating = false.obs;
  final RxBool isHovered = false.obs;
  final RxInt videoFitIndex = 0.obs;
  Rx<ValueKey> videoKey = Rx<ValueKey>(const ValueKey("video_0"));

  final _stateSubject = BehaviorSubject<PlayerState>.seeded(PlayerState.idle);
  final _playingSubject = BehaviorSubject<bool>.seeded(false);
  final _loadingSubject = BehaviorSubject<bool>.seeded(false);
  final _completeSubject = BehaviorSubject<bool>.seeded(false);
  final _errorSubject = PublishSubject<PlayerException>();
  final _widthSubject = BehaviorSubject<int?>.seeded(null);
  final _heightSubject = BehaviorSubject<int?>.seeded(null);

  final List<StreamSubscription> _subscriptions = [];
  StreamSubscription<PiPStatus>? _pipSubscription;

  bool _disposed = false;
  bool _isSwitchingDueToFallback = false;
  bool _isHandlingError = false;
  static const String _floatTag = "global_video_player";
  Timer? _hideTimer;
  late Floating floating;
  LiveRoom? currentFloatRoom;

  UnifiedPlayer? get currentPlayer => _currentPlayer;
  PlayerEngine get currentEngine => _runtimeEngine ?? _defaultEngine ?? PlayerEngine.mediaKit;
  Stream<PlayerState> get onStateChanged => _stateSubject.stream;
  Stream<bool> get onPlaying => _playingSubject.stream;
  Stream<bool> get onLoading => _loadingSubject.stream;
  Stream<bool> get onComplete => _completeSubject.stream;
  Stream<PlayerException> get onError => _errorSubject.stream;
  Stream<int?> get width => _widthSubject.stream;
  Stream<int?> get height => _heightSubject.stream;
  bool get isPlayingNow => _playingSubject.value;

  double get currentVideoRatio {
    final w = _widthSubject.value?.toDouble() ?? 1920;
    final h = _heightSubject.value?.toDouble() ?? 1080;
    if (w <= 0 || h <= 0) return 16 / 9;
    return w / h;
  }

  Future<void> initialize({PlayerEngine engine = PlayerEngine.mediaKit}) async {
    if (_disposed) return;
    _stateSubject.add(PlayerState.initializing);
    try {
      _defaultEngine = engine;
      _runtimeEngine = engine;
      _currentPlayer = await playerPool.getPlayer(engine);
      await _bindPlayerStreams(_currentPlayer!);
      LiveAudioService.setPlayer(_currentPlayer!);
      if (Platform.isAndroid) {
        floating = Floating();
        _pipSubscription?.cancel();
        _pipSubscription = floating.pipStatusStream.listen((status) {
          isInPip.value = status == PiPStatus.enabled;
        });
      }
      isInitialized.value = true;
      _stateSubject.add(PlayerState.initialized);
    } catch (e, s) {
      hasError.value = true;
      final exception = PlayerException(
        message: 'Initialize player failed',
        type: PlayerErrorType.initialization,
        error: e,
        stackTrace: s,
      );
      _errorSubject.add(exception);
      _stateSubject.add(PlayerState.error);
      throw exception;
    }
  }

  Future<void> play(
    String url,
    List<String> playUrls,
    Map<String, String> headers, {
    LiveRoom? room,
  }) async {
    if (_disposed || _isClosing) return;
    final mySessionId = ++_sessionId;

    if (room?.roomId != currentFloatRoom?.roomId) {
      lineManager.reset();
    }
    if (_currentPlayer == null || _runtimeEngine == null) {
      final String savedKey = SettingsService.to.player.videoPlayerKey.v;
      final String validKey = PlayerConsts.engines.containsKey(savedKey) ? savedKey : PlayerConsts.defaultKey;
      _defaultEngine = PlayerConsts.engines[validKey]!;
      _runtimeEngine = _defaultEngine;
      log('No current player, initializing with default engine: _defaultEngine', name: 'PlayerManager');
      await initialize(engine: _defaultEngine!);
    } else if (_runtimeEngine != _defaultEngine && !_isSwitchingDueToFallback) {
      await switchEngine(_defaultEngine!, isManual: false);
    }

    if (!_isSessionValid(mySessionId)) return;

    final player = _currentPlayer;
    if (player == null) {
      throw PlayerException(message: 'Current player is null', type: PlayerErrorType.lifecycle);
    }

    String targetUrl = url;
    List<String> targetPlayUrls = List.from(playUrls);



    _currentUrl = targetUrl;
    _currentPlayUrls = targetPlayUrls;
    _currentHeaders = headers;
    currentFloatRoom = room;
    hasError.value = false;

    try {
      _stateSubject.add(PlayerState.preparing);
      await player.setDataSource(targetUrl, targetPlayUrls, headers, room: room);
      if (!_isSessionValid(mySessionId)) return;

      LiveAudioService.setPlayer(player);
      LiveAudioService.start(room!.roomId!, room.nick ?? "", room.title ?? "", room.avatar);
      videoKey.value = ValueKey("video_{DateTime.now().millisecondsSinceEpoch}");
      _stateSubject.add(PlayerState.ready);
    } on PlayerException catch (e) {
      if (!_isHandlingError && _isSessionValid(mySessionId)) {
        await _handleError(e, sessionId: mySessionId);
      }
    } catch (e, s) {
      log(e.toString());
      if (!_isHandlingError && _isSessionValid(mySessionId)) {
        final exception = PlayerException(
          message: 'Play failed',
          type: PlayerErrorType.unknown,
          error: e,
          stackTrace: s,
        );
        await _handleError(exception, sessionId: mySessionId);
      }
    } finally {
      _isSwitchingDueToFallback = false;
    }
  }

  Future<void> replay() async {
    if (_currentUrl == null) return;
    await play(_currentUrl!, _currentPlayUrls, _currentHeaders, room: currentFloatRoom);
  }

  Future<void> switchEngine(PlayerEngine engine, {bool isManual = false}) async {
    if (_disposed || _isClosing) return;
    if (_runtimeEngine == engine && _currentPlayer != null) return;
    try {
      final oldPlayer = _currentPlayer;
      final oldEngine = _runtimeEngine;
      await _clearSubscriptions();
      final newPlayer = await playerPool.getPlayer(engine);
      _currentPlayer = newPlayer;
      _runtimeEngine = engine;
      if (isManual) _defaultEngine = engine;
      log('Switch engine to engine', name: 'PlayerManager');
      await _bindPlayerStreams(newPlayer);
      LiveAudioService.setPlayer(_currentPlayer!);
      if (oldPlayer != null && oldEngine != null) {
        await _safeDestroyPlayer(oldPlayer, oldEngine);
      }
      videoKey.value = ValueKey("video_{DateTime.now().millisecondsSinceEpoch}");
    } catch (e, s) {
      final exception = PlayerException(
        message: 'Switch engine failed',
        type: PlayerErrorType.lifecycle,
        error: e,
        stackTrace: s,
      );
      _errorSubject.add(exception);
      rethrow;
    }
  }

  Future<void> _safeDestroyPlayer(UnifiedPlayer player, PlayerEngine engine) async {
    try {
      await player.hardDispose();
      await playerPool.removeFromCache(engine);
    } catch (e, s) {
      log("destroy player error: e", stackTrace: s);
    }
  }

  Future<void> togglePlayPause() async {
    if (_currentPlayer == null) return;
    if (isPlayingNow) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> pause() async => await _currentPlayer?.pause();
  Future<void> resume() async => await _currentPlayer?.play();

  Future<void> stop() async {
    await close();
    closeAppFloating();
  }

  Future<void> setVolume(double volume) async {
    await _currentPlayer?.setVolume(volume.clamp(0.0, 1.0));
  }

  void changeVideoFit(int index) => videoFitIndex.value = index;

  Future<void> enablePip() async {
    if (PlatformUtils.isAndroid) {
      final status = await floating.pipStatus;
      if (status == PiPStatus.disabled) {
        final rational = isVerticalVideo.value ? Rational.vertical() : Rational.landscape();
        await floating.enable(ImmediatePiP(aspectRatio: rational));
      }
    } else if (Platform.isWindows) {
      await WindowService().enterWinPiP(currentVideoRatio);
      isInPip.value = true;
    }
  }

  Future<void> exitPip() async {
    if (Platform.isWindows) {
      await WindowService().exitWinPiP();
      GlobalPlayerState.to.reset();
      isInPip.value = false;
    }
  }

  void showAppFloating() {
    floatingManager.disposeFloating(_floatTag);
    _hideTimer?.cancel();
    double maxSide = Platform.isWindows ? 350 : 220;
    double ratio = currentVideoRatio;
    double floatWidth;
    double floatHeight;
    if (ratio >= 1) {
      floatWidth = maxSide;
      floatHeight = maxSide / ratio;
    } else {
      floatHeight = maxSide * 1.2;
      floatWidth = floatHeight * ratio;
      if (floatWidth < 120) {
        floatWidth = 120;
        floatHeight = floatWidth / ratio;
      }
    }

    void resetHideTimer() {
      if (Platform.isAndroid || Platform.isIOS) {
        _hideTimer?.cancel();
        _hideTimer = Timer(const Duration(seconds: 3), () {
          isHovered.value = false;
        });
      }
    }

    floatingManager.createFloating(
      _floatTag,
      FloatingOverlay(
        MouseRegion(
          onEnter: (_) {
            if (Platform.isWindows || Platform.isMacOS) isHovered.value = true;
          },
          onExit: (_) {
            if (Platform.isWindows || Platform.isMacOS) isHovered.value = false;
          },
          child: Container(
            width: floatWidth,
            height: floatHeight,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.black),
            child: Stack(
              children: [
                Positioned.fill(
                  child: getVideoWidget(videoFitIndex.value, fitList: SettingsService.to.player.videoFitArray),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      closeAppFloating();
                      if (currentFloatRoom != null) {
                        AppNavigator.toLiveRoomDetail(liveRoom: currentFloatRoom!);
                      }
                    },
                    child: const SizedBox.expand(),
                  ),
                ),
                Center(
                  child: AnimatedOpacity(
                    opacity: isHovered.value ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !isHovered.value,
                      child: StreamBuilder<bool>(
                        stream: onPlaying,
                        initialData: isPlayingNow,
                        builder: (context, snapshot) {
                          var isPlay = snapshot.data ?? true;
                          return IconButton(
                            iconSize: 42,
                            style: IconButton.styleFrom(backgroundColor: Colors.black45),
                            icon: Icon(
                              isPlay ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              togglePlayPause();
                              resetHideTimer();
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: Obx(
                    () => AnimatedOpacity(
                      opacity: isHovered.value ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !isHovered.value,
                        child: IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                          style: IconButton.styleFrom(backgroundColor: Colors.black45),
                          icon: const Icon(Icons.close, color: Colors.white, size: 20),
                          onPressed: () async {
                            await stop();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        right: 50,
        top: 100,
        slideType: FloatingEdgeType.onRightAndTop,
        params: FloatingParams(isSnapToEdge: false, snapToEdgeSpace: 10, dragOpacity: 0.8),
      ),
    );
    floatingManager.getFloating(_floatTag).open(Get.context!);
    isFloating.value = true;
    if (Platform.isAndroid || Platform.isIOS) {
      isHovered.value = true;
      resetHideTimer();
    }
  }

  void closeAppFloating() {
    if (!isFloating.value) return;
    floatingManager.disposeFloating(_floatTag);
    isFloating.value = false;
  }

  Widget buildPiPOverlay() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MouseRegion(
        onEnter: (_) => isHovered.value = true,
        onExit: (_) => isHovered.value = false,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Colors.black),
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => windowManager.startDragging(),
                onDoubleTap: () async {
                  await exitPip();
                },
                child: getVideoWidget(videoFitIndex.value, fitList: SettingsService.to.player.videoFitArray),
              ),
              Center(
                child: Obx(
                  () => AnimatedOpacity(
                    opacity: isHovered.value ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: StreamBuilder<bool>(
                      stream: onPlaying,
                      initialData: isPlayingNow,
                      builder: (context, snapshot) {
                        var isPlay = snapshot.data ?? true;
                        return IconButton(
                          iconSize: 42,
                          style: IconButton.styleFrom(backgroundColor: Colors.black45),
                          icon: Icon(
                            isPlay ? Icons.pause_circle_filled : Icons.play_circle_filled,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            togglePlayPause();
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Obx(
                  () => AnimatedOpacity(
                    opacity: isHovered.value ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () async {
                        await exitPip();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }



  Widget getVideoWidget(int fitIndex, {Widget? controls, required List<BoxFit> fitList}) {
    return PureLivePipWidget(
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.all(0),
        child: StreamBuilder<bool>(
          stream: onPlaying,
          initialData: isPlayingNow,
          builder: (context, snapshot) {
            if (_currentPlayer == null) {
              return _buildPlaceholder();
            }
            final boxFit = fitList[fitIndex];
            final content = KeyedSubtree(
              key: videoKey.value,
              child: Container(
                color: Colors.black,
                width: double.infinity,
                height: double.infinity,
                child: Stack(
                  children: [
                    Positioned.fill(
                        child: Container(
                          color: Colors.black,
                          child: FittedBox(
                            fit: boxFit,
                            clipBehavior: Clip.hardEdge,
                            child: StreamBuilder<List<int?>>(
                              stream: CombineLatestStream.list([width, height]),
                              builder: (context, snapshot) {
                                final vW = snapshot.data?[0]?.toDouble() ?? 1920.0;
                                final vH = snapshot.data?[1]?.toDouble() ?? 1080.0;
                                return SizedBox(width: vW, height: vH, child: _currentPlayer!.getVideoWidget());
                              },
                            ),
                          ),
                        ),
                      ),
                    if (controls != null) Positioned.fill(child: controls),
                  ],
                ),
              ),
            );
            if (!Platform.isAndroid) {
              return content;
            }
            return PiPSwitcher(floating: floating, childWhenEnabled: content, childWhenDisabled: content);
          },
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.black,
      child: AppStatusView(type: AppStatusType.loading, title: "", subtitle: "", iconColor: Colors.white),
    );
  }

  Future<void> close() async {
    _sessionId++;
    _isClosing = true;
    await LiveAudioService.stop();
    SettingsService.to.player.useHardStopOnExit.v ? await hardDispose() : await softStop();
    _isClosing = false;
  }

  Future<void> softStop() async {
    lineManager.reset();
    try {
      if (_stateSubject.value == PlayerState.error) {
        await hardDispose();
        return;
      }
      await _currentPlayer?.softStop();
      _stateSubject.add(PlayerState.idle);
      _playingSubject.add(false);
    } catch (e) {
      await hardDispose();
    }
  }

  Future<void> hardDispose() async {
    lineManager.reset();
    await _clearSubscriptions();
    if (_runtimeEngine != null) {
      await playerPool.removeFromCache(_runtimeEngine!);
    }
    _currentPlayer = null;
    _runtimeEngine = null;
    isInitialized.value = false;
  }

  Future<void> retry() async {
    await replay();
  }

  /// 线路/引擎全部失败后，请求上层重新获取播放地址（自动恢复，带次数限制防死循环）
  Future<void> _tryRefreshUrls(PlayerException error) async {
    if (_disposed || _isClosing) return;
    final isRecoverable = error.type == PlayerErrorType.network ||
        error.type == PlayerErrorType.source ||
        error.type == PlayerErrorType.initialization ||
        error.type == PlayerErrorType.native;
    if (!isRecoverable || onRefreshUrls == null || _refreshUrlsCount >= 2) return;
    _refreshUrlsCount++;
    log("🔄 线路/引擎耗尽，重新获取播放地址(#$_refreshUrlsCount)");
    try {
      await onRefreshUrls?.call();
    } catch (e) {
      log("refresh urls failed: $e");
    }
  }

  Future<void> _handleError(PlayerException error, {int? sessionId}) async {
    if (_disposed || _isClosing) return;
    if (_isHandlingError) {
      log("skip duplicated error handling: {error.message}");
      return;
    }
    final mySessionId = sessionId ?? _sessionId;
    if (!_isSessionValid(mySessionId)) return;

    _isHandlingError = true;
    try {
      hasError.value = true;
      _errorSubject.add(error);
      _stateSubject.add(PlayerState.error);

      bool lineSwitched = false;
      if ((error.type == PlayerErrorType.network || error.type == PlayerErrorType.source) &&
          _currentPlayUrls.length > 1) {
        lineManager.markFailed(_currentUrl!);
        if (!lineManager.hasAvailable(_currentPlayUrls)) {
          log("no available lines, fallback engine");
        } else {
          final nextLine = lineManager.next(_currentPlayUrls);
          if (nextLine != _currentUrl) {
            lineSwitched = true;
            log("switch line => nextLine");
            await Future.delayed(const Duration(seconds: 2));
            if (!_isSessionValid(mySessionId)) return;
            await play(nextLine, _currentPlayUrls, _currentHeaders, room: currentFloatRoom);
            return;
          }
        }
      }

      log(error.type.toString());
      if (!lineSwitched && fallbackManager.shouldFallback(error)) {
        final nextEngine = await fallbackManager.fallback(_runtimeEngine!, error);
        if (nextEngine == _runtimeEngine) {
          // 单引擎(mediaKit)无降级目标：不 return，继续走下方自动恢复(重取流地址)
          log("skip fallback: 单引擎无降级目标，尝试自动恢复(重取流地址)");
        } else {
          log(
            "fallback engine: "
            "${_runtimeEngine?.name} -> ${nextEngine.name}",
          );
          _isSwitchingDueToFallback = true;
          await Future.delayed(const Duration(milliseconds: 1200));
          if (!_isSessionValid(mySessionId)) return;
          await switchEngine(nextEngine, isManual: false);
          await Future.delayed(const Duration(milliseconds: 500));
          if (!_isSessionValid(mySessionId)) return;
          await replay();
          return;
        }
      }

      // ★ 所有可自动恢复手段（切线路/降引擎）穷尽：请求上层重新获取流地址
      // 抖音流地址有时效性（通常数小时），且偶发被风控返回空；刷新后通常即可恢复
      if (!lineSwitched) {
        await _tryRefreshUrls(error);
      }
    } catch (e, s) {
      log("_handleError failed: $e", stackTrace: s);
    } finally {
      _isHandlingError = false;
    }
  }

  Future<void> _bindPlayerStreams(UnifiedPlayer player) async {
    await _clearSubscriptions();
    _subscriptions.add(
      player.onPlaying.listen((event) async {
        _playingSubject.add(event);
        if (event) {
          hasError.value = false;
          _refreshUrlsCount = 0;
          _stateSubject.add(PlayerState.playing);
          if (_isSwitchingDueToFallback) {
            _isSwitchingDueToFallback = false;
          }
        } else {
          _stateSubject.add(PlayerState.paused);
        }
      }),
    );
    _subscriptions.add(
      player.onLoading.listen((event) {
        _loadingSubject.add(event);
        if (event && _stateSubject.value != PlayerState.buffering) {
          _stateSubject.add(PlayerState.buffering);
        }
      }),
    );
    _subscriptions.add(
      player.onComplete.listen((event) {
        _completeSubject.add(event);
      }),
    );
    _subscriptions.add(
      player.onStateChanged.listen((event) {
        _stateSubject.add(event);
      }),
    );
    _subscriptions.add(
      player.onError.listen((error) {
        if (!_isHandlingError) {
          _handleError(error);
        }
      }),
    );
    _subscriptions.add(
      player.width.listen((event) {
        _widthSubject.add(event);
      }),
    );
    _subscriptions.add(
      player.height.listen((event) {
        _heightSubject.add(event);
      }),
    );
    _subscriptions.add(
      CombineLatestStream.combine2<int?, int?, bool>(
        width.where((w) => w != null && w > 0),
        height.where((h) => h != null && h > 0),
        (w, h) => h! >= w!,
      ).distinct().listen((event) {
        isVerticalVideo.value = event;
      }),
    );
  }

  Future<void> _clearSubscriptions() async {
    if (_subscriptions.isEmpty) return;
    for (final item in _subscriptions.toList()) {
      await item.cancel();
    }
    _subscriptions.clear();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _sessionId++;
    _isClosing = true;
    _hideTimer?.cancel();
    closeAppFloating();
    _pipSubscription?.cancel();
    await _clearSubscriptions();
    await playerPool.disposeAll();
    await Future.wait([
      _stateSubject.close(),
      _playingSubject.close(),
      _loadingSubject.close(),
      _completeSubject.close(),
      _errorSubject.close(),
      _widthSubject.close(),
      _heightSubject.close(),
    ]);
  }
}
