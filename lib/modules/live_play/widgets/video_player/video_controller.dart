import 'dart:io';
import 'dart:async';
import 'dart:developer';
import 'video_controller_panel.dart';
import 'package:pure_live/common/index.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flame_barrage/flame_barrage.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:pure_live/player/utils/fullscreen.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:pure_live/modules/live_play/load_type.dart';
import 'package:pure_live/common/global/platform_utils.dart';
import 'package:scrollview_observer/scrollview_observer.dart';
import 'package:pure_live/player/models/player_exception.dart';
import 'package:pure_live/player/models/player_engine.dart';
import 'package:pure_live/modules/live_play/player_state.dart';
import 'package:pure_live/player/models/player_error_type.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';

class VideoController with ChangeNotifier {
  final LiveRoom room;
  String datasource;
  List<String> playUrls;
  final bool allowScreenKeepOn;
  final bool allowFullScreen;
  final Map<String, String> headers;
  final isVertical = false.obs;

  ScreenBrightness? _brightnessController;
  ScreenBrightness? get brightnessController {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    _brightnessController ??= ScreenBrightness();
    return _brightnessController;
  }

  double initBrightness = 0.0;

  final String qualiteName;

  final int currentLineIndex;

  final int currentQuality;

  bool get supportWindowFull => Platform.isWindows || Platform.isLinux;

  late final VolumeController _volumeController;

  late final StreamSubscription<double> _subscription;

  GlobalKey<BrightnessVolumnDargAreaState> brightnessKey = GlobalKey<BrightnessVolumnDargAreaState>();

  LivePlayController livePlayController = Get.find<LivePlayController>();

  StreamSubscription<PlayerException>? _errorSub;
  StreamSubscription<bool>? _pipSub;
  StreamSubscription<bool>? _playingSub;
  /// 内核提示只出一次（每次进房的新 VideoController 实例都会重置）
  bool _kernelToastShown = false;
  Timer? showControllerTimer;
  final showController = true.obs;
  final showLocked = false.obs;
  final danmuKey = GlobalKey();
  final isMenuOpen = false.obs;

  Timer? _debounceTimer;
  Timer? _hideVolumeTimer;
  final showVolume = false.obs;

  void updateVolumn(double volume) {
    _hideVolumeTimer?.cancel();
    showVolume.value = true;
    _hideVolumeTimer = Timer(const Duration(seconds: 1), () {
      showVolume.value = false;
    });
  }

  void enableController() {
    showControllerTimer?.cancel();
    showControllerTimer = Timer(const Duration(seconds: 2), () {
      showController.value = false;
    });
    showController.value = true;
  }

  void stopHideController() {
    showControllerTimer?.cancel();
  }

  final hideDanmaku = false.obs;
  final danmakuArea = 1.0.obs;
  final danmakuTopArea = 0.0.obs;
  final danmakuBottomArea = 0.0.obs;
  final danmakuSpeed = 8.0.obs;
  final danmakuFontSize = 16.0.obs;
  final danmakuFontBorder = 4.obs;
  final danmakuOpacity = 1.0.obs;
  final enableDanmakuStroke = true.obs;
  final danmakuFps = 60.obs;
  final danmakuFontFamilyName = ''.obs;
  VideoController({
    required this.room,
    required this.datasource,
    required this.headers,
    required this.playUrls,
    this.allowScreenKeepOn = false,
    this.allowFullScreen = true,
    BoxFit fitMode = BoxFit.contain,
    required this.qualiteName,
    required this.currentLineIndex,
    required this.currentQuality,
  }) {
    danmakuController = BarrageController();

    hideDanmaku.value = SettingsService.to.danmaku.hideDanmaku.v;
    danmakuTopArea.value = SettingsService.to.danmaku.danmakuTopArea.v;
    danmakuBottomArea.value = SettingsService.to.danmaku.danmakuBottomArea.v;
    danmakuSpeed.value = SettingsService.to.danmaku.danmakuSpeed.v;
    danmakuFontSize.value = SettingsService.to.danmaku.danmakuFontSize.v;
    danmakuFontBorder.value = SettingsService.to.danmaku.danmakuFontBorder.v.toInt();
    danmakuOpacity.value = SettingsService.to.danmaku.danmakuOpacity.v;
    enableDanmakuStroke.value = SettingsService.to.danmaku.enableDanmakuStroke.v;
    danmakuFontFamilyName.value = SettingsService.to.danmaku.danmakuFontFamilyName.v;
    initPagesConfig();
  }

  void initPagesConfig() {
    scheduleObserverController = ListObserverController(controller: scheduleScrollController);
    if (allowScreenKeepOn) WakelockPlus.enable();
    initVideoController();
    initDanmaku();
    initBattery();
  }

  // Battery level control
  final Battery _battery = Battery();
  final batteryLevel = 100.obs;

  late BarrageController danmakuController;

  final ScrollController scheduleScrollController = ScrollController();
  late ListObserverController scheduleObserverController;
  bool hasScrolledToLive = false;
  void initBattery() {
    if (Platform.isAndroid || Platform.isIOS) {
      _battery.batteryLevel.then((value) => batteryLevel.value = value);
      _battery.onBatteryStateChanged.listen((BatteryState state) async {
        batteryLevel.value = await _battery.batteryLevel;
      });
    }
  }

  void initPlayerListener() {
    final manager = GlobalPlayerService.instance.playerManager;
    _errorSub?.cancel();
    _errorSub = manager.onError.listen((error) {
      log('error: ${error.toString()}', name: 'initPlayerListener');
      _handlePlayerError(error);
    });
    // ★ 播放成功时提示当前内核（进直播间第一条播放事件，一次即可）
    _playingSub?.cancel();
    _playingSub = manager.onPlaying.listen((playing) {
      if (!playing || _kernelToastShown) return;
      _kernelToastShown = true;
      final engine = manager.currentEngine;
      final engineName = engine == PlayerEngine.videoPlayer ? i18n('player_system') : i18n('player_mpv');
      ToastUtil.show('[$engineName]');
    });
  }

  void _handlePlayerError(PlayerException error) {
    switch (error.type) {
      case PlayerErrorType.network:
        ToastUtil.show(i18n("error_network"));
        break;
      case PlayerErrorType.source:
        ToastUtil.show(i18n("error_source"));
        break;
      case PlayerErrorType.codec:
        ToastUtil.show(i18n("error_codec"));
        break;
      case PlayerErrorType.native:
        ToastUtil.show(i18n("error_native"));
        break;
      case PlayerErrorType.initialization:
        ToastUtil.show(i18n("error_initialization"));
        break;
      case PlayerErrorType.texture:
        ToastUtil.show(i18n("error_texture"));
        break;
      case PlayerErrorType.lifecycle:
        ToastUtil.show(i18n("error_lifecycle"));
        break;
      case PlayerErrorType.unknown:
        ToastUtil.show(i18n("error_unknown"));
        break;
    }
  }



  void initVideoController() async {
    // ★ 确保播放器已就绪（单飞初始化，秒进房时不会因 late 未赋值卡 loading）
    await GlobalPlayerService.instance.initialize();
    final playerManager = GlobalPlayerService.instance.playerManager;
    if (PlatformUtils.isMobile) {
      _volumeController = VolumeController.instance;
      _volumeController.showSystemUI = false;
      registerVolumeListener();
      // 音量恢复统一由 MediaKitAdapter.setDataSource 处理（房间音量/全局静音）
    }
    playerManager.play(datasource, playUrls, headers, room: room);
    initPlayerListener();
    // 处理默认全屏

    Future.delayed(Duration(milliseconds: 1000), () {
      if (SettingsService.to.app.enableFullScreenDefault.v) {
        livePlayController.setFullScreen();
        enterFullScreen();
        GlobalPlayerState.to.isFullscreen.value = true;
        enableController();
      }
    });

  }

  void retryRoom() async {
    var liveRoom = await Sites.of(
      room.platform!,
    ).liveSite.getRoomDetail(roomId: room.roomId!, platform: room.platform!);
    if (liveRoom.liveStatus == LiveStatus.offline) {
      livePlayController.setNormalScreen();
      ToastUtil.show(i18n("room_offline"));
    } else {
      changeLine();
    }
  }

  void debounceListen(Function? func, [int delay = 1000]) {
    if (_debounceTimer != null) {
      _debounceTimer?.cancel();
    }
    _debounceTimer = Timer(Duration(milliseconds: delay), () {
      func?.call();
      _debounceTimer = null;
    });
  }

  void initDanmaku() {
    final dm = SettingsService.to.danmaku;

    hideDanmaku.value = dm.hideDanmaku.v;
    ever<bool>(hideDanmaku, (data) {
      dm.hideDanmaku.v = data;
    });

    danmakuArea.value = dm.danmakuArea.v;
    danmakuTopArea.value = dm.danmakuTopArea.v;
    danmakuBottomArea.value = dm.danmakuBottomArea.v;
    danmakuSpeed.value = dm.danmakuSpeed.v;
    danmakuFontSize.value = dm.danmakuFontSize.v;
    danmakuFontBorder.value = dm.danmakuFontBorder.v.toInt();
    danmakuOpacity.value = dm.danmakuOpacity.v;
    enableDanmakuStroke.value = dm.enableDanmakuStroke.v;
    danmakuFps.value = dm.danmakuFps.v;
    final List<Rx> visualProperties = [
      danmakuArea,
      danmakuTopArea,
      danmakuBottomArea,
      danmakuSpeed,
      danmakuFontSize,
      danmakuFontBorder,
      danmakuOpacity,
      enableDanmakuStroke,
      danmakuFps,
    ];

    for (final rxProperty in visualProperties) {
      ever(rxProperty, (_) => updateDanmaku());
    }

    ever<double>(danmakuArea, (v) => dm.danmakuArea.v = v);
    ever<double>(danmakuTopArea, (v) => dm.danmakuTopArea.v = v);
    ever<double>(danmakuBottomArea, (v) => dm.danmakuBottomArea.v = v);
    ever<double>(danmakuSpeed, (v) => dm.danmakuSpeed.v = v);
    ever<double>(danmakuFontSize, (v) => dm.danmakuFontSize.v = v);
    ever<int>(danmakuFontBorder, (v) => dm.danmakuFontBorder.v = v.toDouble());
    ever<double>(danmakuOpacity, (v) => dm.danmakuOpacity.v = v);
    ever<bool>(enableDanmakuStroke, (v) => dm.enableDanmakuStroke.v = v);
    ever<int>(danmakuFps, (v) => dm.danmakuFps.v = v);
  }

  void updateDanmaku() {
    danmakuController.updateConfig(
      BarrageConfig(
        fontSize: danmakuFontSize.value,
        area: danmakuArea.value,
        topAreaDistance: danmakuTopArea.value,
        bottomAreaDistance: danmakuBottomArea.value,
        baseSpeed: danmakuSpeed.value,
        opacity: danmakuOpacity.value,
        fontWeight: FontWeight.values[danmakuFontBorder.value],
        showStroke: enableDanmakuStroke.value,
        fps: danmakuFps.value,
      ),
    );
  }

  void sendDanmaku(LiveMessage msg) {
    if (hideDanmaku.value) return;
    // 弹幕是直播间聊天流，不受播放状态(isPlayingNow)限制，
    // 避免切清晰度/全屏时播放状态短暂异常导致弹幕被拦截、偶发无弹幕。
    danmakuController.send(
      BarrageItem(content: msg.message, textColor: Color.fromARGB(255, msg.color.r, msg.color.g, msg.color.b)),
    );
  }


  @override
  void dispose() {
    _errorSub?.cancel();
    _errorSub = null;
    _pipSub?.cancel();
    _pipSub = null;
    _playingSub?.cancel();
    _playingSub = null;
    showControllerTimer?.cancel();
    _debounceTimer?.cancel();
    _hideVolumeTimer?.cancel();
    _volumeSaveTimer?.cancel();
    unawaited(destroy());
    super.dispose();
  }

  void refresh() async {
    _errorSub?.cancel();
    _errorSub = null;
    _pipSub?.cancel();
    _pipSub = null;
    _playingSub?.cancel();
    _playingSub = null;
    GlobalPlayerService.instance.playerManager.close();
    await destroy();
    livePlayController.onInitPlayerState(reloadDataType: ReloadDataType.refreash);
  }

  void clearListener() {
    _errorSub?.cancel();
    _errorSub = null;
    _pipSub?.cancel();
    _pipSub = null;
    _playingSub?.cancel();
    _playingSub = null;
  }

  void changeLine() async {
    _errorSub?.cancel();
    _errorSub = null;
    _pipSub?.cancel();
    _pipSub = null;
    _playingSub?.cancel();
    _playingSub = null;

    GlobalPlayerService.instance.playerManager.close();
    await destroy();
    livePlayController.onInitPlayerState(reloadDataType: ReloadDataType.changeLine, line: currentLineIndex);
  }

  Future<void> destroy() async {
    if (Platform.isAndroid || Platform.isIOS) {
      if (allowScreenKeepOn) WakelockPlus.disable();
      unawaited(_subscription.cancel());
      _volumeController.removeListener();
    }
  }

  /// 音量保存防抖：拖动音量条高频回调只落盘最后一次（避免频繁写 Hive）
  Timer? _volumeSaveTimer;

  void _debouncedSaveVolume(double volume) {
    _volumeSaveTimer?.cancel();
    _volumeSaveTimer = Timer(const Duration(milliseconds: 400), () {
      room.saveCurrentVolume(volume);
    });
  }

  void setVideoFit(int index) {
    GlobalPlayerService.instance.playerManager.changeVideoFit(index);
  }

  void exitFullScreen() async {
    WindowService().doExitFullScreen();
    GlobalPlayerState.to.isFullscreen.value = false;
  }

  void toggleFullScreen() async {
    showLocked.value = false;
    showControllerTimer?.cancel();
    GlobalPlayerState.to.isWindowFullscreen.value = false;
    Timer(const Duration(seconds: 2), () {
      enableController();
    });
    if (GlobalPlayerState.to.isFullscreen.value) {
      livePlayController.setNormalScreen();
      WindowService().doExitFullScreen();
      GlobalPlayerState.to.isFullscreen.value = false;
    } else {
      livePlayController.setFullScreen();
      enterFullScreen();
      GlobalPlayerState.to.isFullscreen.value = true;
    }
    enableController();
  }

  void enterFullScreen() {
    WindowService().doEnterFullScreen();
    GlobalPlayerState.to.isFullscreen.value = true;
    if (GlobalPlayerService.instance.playerManager.isVerticalVideo.value) {
      WindowService().verticalScreen();
    } else {
      WindowService().landScape();
    }
  }

  // 半屏显示
  void toggleWindowFullScreen() {
    showLocked.value = false;
    showControllerTimer?.cancel();
    Timer(const Duration(seconds: 2), () {
      enableController();
    });
    if (GlobalPlayerState.to.isWindowFullscreen.value) {
      livePlayController.setNormalScreen();
      GlobalPlayerState.to.isWindowFullscreen.value = false;
    } else {
      livePlayController.setWidescreen();
      GlobalPlayerState.to.isWindowFullscreen.value = true;
    }
    GlobalPlayerState.to.isFullscreen.value = false;
    enableController();
  }

  // 注册音量变化监听器
  void registerVolumeListener() {
    _subscription = _volumeController.addListener((volume) {
      _debouncedSaveVolume(volume);
    }, fetchInitialVolume: true);
  }

  // volume & brightness
  Future<double?> volume() async {
    if (Platform.isWindows) {
      return room.getSavedVolume();
    }
    return await _volumeController.getVolume();
  }

  Future<double> brightness() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return await brightnessController!.application;
    }
    throw Exception('Brightness not supported on this platform');
  }

  void setVolume(double value) async {
    if (Platform.isWindows) {
      GlobalPlayerService.instance.playerManager.setVolume(value);
    } else {
      await _volumeController.setVolume(value);
    }
    _debouncedSaveVolume(value);
  }

  void setBrightness(double value) async {
    if (Platform.isAndroid || Platform.isIOS) {
      await brightnessController!.setApplicationScreenBrightness(value);
    }
  }
}
