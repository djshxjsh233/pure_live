import 'dart:async';
import 'dart:io';
import 'package:floating/floating.dart';
import 'package:flutter/material.dart';
import 'package:flutter_floating/flutter_floating.dart';
import 'package:rxdart/rxdart.dart';
import 'package:window_manager/window_manager.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/routes/app_navigation.dart';
import 'package:pure_live/player/core/player_manager.dart';
import 'package:pure_live/player/utils/pip_window_widget.dart';

/// 播放器 UI 层：悬浮窗 / PiP / 视频渲染组件
/// 由 PlayerManager 薄委托调用，与播放内核解耦。
class PlayerUi {
  static const String floatTag = "global_video_player";

  static Timer? _hideTimer;

  static void showAppFloating(PlayerManager manager) {
    floatingManager.disposeFloating(floatTag);
    _hideTimer?.cancel();
    double maxSide = Platform.isWindows ? 350 : 220;
    double ratio = manager.currentVideoRatio;
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
          manager.isHovered.value = false;
        });
      }
    }

    floatingManager.createFloating(
      floatTag,
      FloatingOverlay(
        MouseRegion(
          onEnter: (_) {
            if (Platform.isWindows || Platform.isMacOS) manager.isHovered.value = true;
          },
          onExit: (_) {
            if (Platform.isWindows || Platform.isMacOS) manager.isHovered.value = false;
          },
          child: Container(
            width: floatWidth,
            height: floatHeight,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.black),
            child: Stack(
              children: [
                Positioned.fill(
                  child: buildVideo(manager, manager.videoFitIndex.value, fitList: SettingsService.to.player.videoFitArray),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      closeAppFloating(manager);
                      if (manager.currentFloatRoom != null) {
                        AppNavigator.toLiveRoomDetail(liveRoom: manager.currentFloatRoom!);
                      }
                    },
                    child: const SizedBox.expand(),
                  ),
                ),
                Center(
                  child: AnimatedOpacity(
                    opacity: manager.isHovered.value ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !manager.isHovered.value,
                      child: StreamBuilder<bool>(
                        stream: manager.onPlaying,
                        initialData: manager.isPlayingNow,
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
                              manager.togglePlayPause();
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
                      opacity: manager.isHovered.value ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !manager.isHovered.value,
                        child: IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                          style: IconButton.styleFrom(backgroundColor: Colors.black45),
                          icon: const Icon(Icons.close, color: Colors.white, size: 20),
                          onPressed: () async {
                            await manager.stop();
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
    floatingManager.getFloating(floatTag).open(Get.context!);
    manager.isFloating.value = true;
    if (Platform.isAndroid || Platform.isIOS) {
      manager.isHovered.value = true;
      resetHideTimer();
    }
  }

  static void closeAppFloating(PlayerManager manager) {
    if (!manager.isFloating.value) return;
    floatingManager.disposeFloating(floatTag);
    manager.isFloating.value = false;
  }

  static Widget buildPiPOverlay(PlayerManager manager) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MouseRegion(
        onEnter: (_) => manager.isHovered.value = true,
        onExit: (_) => manager.isHovered.value = false,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Colors.black),
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => windowManager.startDragging(),
                onDoubleTap: () async {
                  await manager.exitPip();
                },
                child: buildVideo(manager, manager.videoFitIndex.value, fitList: SettingsService.to.player.videoFitArray),
              ),
              Center(
                child: Obx(
                  () => AnimatedOpacity(
                    opacity: manager.isHovered.value ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: StreamBuilder<bool>(
                      stream: manager.onPlaying,
                      initialData: manager.isPlayingNow,
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
                            manager.togglePlayPause();
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
                    opacity: manager.isHovered.value ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () async {
                        await manager.exitPip();
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

  static Widget buildVideo(PlayerManager manager, int fitIndex,
      {Widget? controls, required List<BoxFit> fitList}) {
    return PureLivePipWidget(
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.all(0),
        child: StreamBuilder<bool>(
          stream: manager.onPlaying,
          initialData: manager.isPlayingNow,
          builder: (context, snapshot) {
            if (manager.currentPlayer == null) {
              return buildPlaceholder();
            }
            final boxFit = fitList[fitIndex];
            final content = KeyedSubtree(
              key: manager.videoKey.value,
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
                            stream: CombineLatestStream.list([manager.width, manager.height]),
                            builder: (context, snapshot) {
                              final vW = snapshot.data?[0]?.toDouble() ?? 1920.0;
                              final vH = snapshot.data?[1]?.toDouble() ?? 1080.0;
                              return SizedBox(width: vW, height: vH, child: manager.currentPlayer!.getVideoWidget());
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
            return PiPSwitcher(floating: manager.floating, childWhenEnabled: content, childWhenDisabled: content);
          },
        ),
      ),
    );
  }

  static Widget buildPlaceholder() {
    return Container(
      color: Colors.black,
      child: AppStatusView(type: AppStatusType.loading, title: "", subtitle: "", iconColor: Colors.white),
    );
  }
}