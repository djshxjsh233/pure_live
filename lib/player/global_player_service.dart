import 'dart:developer';
import 'core/player_pool.dart';
import 'core/player_manager.dart';
import 'models/player_engine.dart';
import 'adapters/media_kit_adapter.dart';
import 'adapters/video_player_adapter.dart';
import 'core/line_fallback_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'core/engine_fallback_manager.dart';

class GlobalPlayerService {
  GlobalPlayerService._();

  static final GlobalPlayerService instance = GlobalPlayerService._();

  late PlayerManager playerManager;

  bool _initialized = false;

  static Future<void>? _initFuture;

  bool get initialized => _initialized;

  /// 单飞初始化：并发调用(启动预热 + 用户秒进房)复用同一个 Future，
  /// 避免双建原生播放器导致灰屏/卡顿
  Future<void> initialize({PlayerEngine defaultEngine = PlayerEngine.mediaKit}) {
    if (_initialized) return Future.value();
    return _initFuture ??= _doInitialize(defaultEngine);
  }

  Future<void> _doInitialize(PlayerEngine defaultEngine) async {
    try {
      // ★ 先同步创建管理器（在首个 await 之前）——让 late playerManager 立即可用，
      // 避免用户秒进房时访问未初始化的 late 变量 -> LateInitializationError 卡 loading
      final playerPool = PlayerPool(
        factory: (engine) async {
          switch (engine) {
            case PlayerEngine.mediaKit:
              return MediaKitAdapter();
            case PlayerEngine.videoPlayer:
              return VideoPlayerAdapter();
          }
        },
      );
      playerManager = PlayerManager(
        playerPool: playerPool,
        fallbackManager: EngineFallbackManager(
          defaultEngine: PlayerEngine.mediaKit,
          supportedEngines: [PlayerEngine.mediaKit, PlayerEngine.videoPlayer],
        ),
        lineManager: LineFallbackManager(),
      );

      MediaKit.ensureInitialized();

      // 3. Perform basic initialization (Pre-warms the default engine)
      await playerManager.initialize(engine: defaultEngine);
      _initialized = true;
      log("GlobalPlayerService: Initialized successfully.", name: "GlobalPlayerService");
    } catch (e) {
      _initFuture = null; // 失败清锁，允许重试
      log("GlobalPlayerService: Failed to initialize: $e", name: "GlobalPlayerService", error: e);
    }
  }

  /// Global dispose - Call this only when the app is being destroyed
  Future<void> dispose() async {
    if (!_initialized) return;
    await playerManager.dispose();
    _initialized = false;
    log("GlobalPlayerService: Disposed.", name: "GlobalPlayerService");
  }
}
