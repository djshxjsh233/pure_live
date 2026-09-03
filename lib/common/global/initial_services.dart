import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/auth/auth_controller.dart';
import 'package:pure_live/modules/live_play/player_state.dart';
import 'package:pure_live/recorder/services/cache_service.dart';
import 'package:pure_live/routes/route_observer_controller.dart';
import 'package:pure_live/recorder/services/stream_resolver_service.dart';
import 'package:pure_live/recorder/pages/recorder/recorder_controller.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:pure_live/recorder/pages/record_settings/record_settings_controller.dart';

class InitialServices {
  static void initGlobalServices() {
    Get.put(SettingsService(), permanent: true);
    Get.put(RouteObserverController(), permanent: true);
  }

  static void initLazyControllers() {
    // 关注
    Get.lazyPut(() => FavoriteController(), fenix: true);
    // iptv频道
    // 热门
    Get.lazyPut(() => PopularController(), fenix: true);
    // 分区
    Get.lazyPut(() => AreasController(), fenix: true);
    // 播放器状态
    Get.lazyPut(() => GlobalPlayerState(), fenix: true);
  }

  static Future<void> init() async {
    initGlobalServices();
    initLazyControllers();
    _initHeavyServicesInBackground();
  }

  static void _initHeavyServicesInBackground() {
    // ★ 辅助服务(录播/流解析/登录)全部改成"注册+按需实例化"：
    //  - FFmpegKit 原生库保持后台预热(录播前置, 不占启动路径)
    //  - 服务实例延迟到首次 Get.find 时才创建(fenix),
    //    主流程(播放/直播间构造)不依赖它们的注册时序
    Future.delayed(const Duration(seconds: 3), () {
      try {
        FFmpegKitExtended.initialize();
        Get.lazyPut(() => CacheService(), fenix: true);
        Get.lazyPut(() => RecordSettingsController(), fenix: true);
        Get.lazyPut(() => RecorderController(), fenix: true);
        Get.lazyPut(() => StreamResolverService(), fenix: true);
        Get.lazyPut(() => AuthController(), fenix: true);
      } catch (_) {}
    });
  }
}
