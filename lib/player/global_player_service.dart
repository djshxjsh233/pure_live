import 'dart:developer';
import 'core/player_pool.dart';
import 'core/player_manager.dart';
import 'models/player_engine.dart';
import 'adapters/media_kit_adapter.dart';
import 'core/line_fallback_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'core/engine_fallback_manager.dart';
import 'package:pure_live/common/global/platform_utils.dart';

class GlobalPlayerService {
  GlobalPlayerService._();

  static final GlobalPlayerService instance = GlobalPlayerService._();

  late final PlayerManager playerManager;

  bool _initialized = false;

  bool get initialized => _initialized;

  Future<void> initialize({PlayerEngine defaultEngine = PlayerEngine.mediaKit}) async {
    if (_initialized) return;

    MediaKit.ensureInitialized();
    // 1. Setup the Pool with a factory that knows how to create each Adapter
    // （精简版：仅保留 MPV(media_kit) 播放器内核）
    final playerPool = PlayerPool(
      factory: (engine) async {
        switch (engine) {
          case PlayerEngine.mediaKit:
            return MediaKitAdapter();
        }
      },
    );

    // 2. Instantiate the Orchestrator with all its specialized managers
    playerManager = PlayerManager(
      playerPool: playerPool,
      fallbackManager: EngineFallbackManager(
        defaultEngine: PlayerEngine.mediaKit,
        supportedEngines: [PlayerEngine.mediaKit],
      ),
      lineManager: LineFallbackManager(),
    );

    // 3. Perform basic initialization (Pre-warms the default engine)
    try {
      await playerManager.initialize(engine: defaultEngine);
      _initialized = true;
      log("GlobalPlayerService: Initialized successfully.", name: "GlobalPlayerService");
    } catch (e) {
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
