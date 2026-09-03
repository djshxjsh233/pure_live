import '../models/player_engine.dart';
import '../interface/unified_player_interface.dart';

class PlayerPool {
  final Map<PlayerEngine, UnifiedPlayer> _cache = {};
  /// 创建中的 Future（防止并发 getPlayer 双建原生播放器）
  final Map<PlayerEngine, Future<UnifiedPlayer>> _pending = {};

  final Future<UnifiedPlayer> Function(PlayerEngine) factory;

  PlayerPool({required this.factory});

  Future<UnifiedPlayer> getPlayer(PlayerEngine engine) async {
    if (_cache.containsKey(engine)) {
      return _cache[engine]!;
    }
    final inflight = _pending[engine];
    if (inflight != null) {
      return inflight;
    }
    final future = _createPlayer(engine);
    _pending[engine] = future;
    try {
      final player = await future;
      _cache[engine] = player;
      return player;
    } finally {
      _pending.remove(engine);
    }
  }

  Future<UnifiedPlayer> _createPlayer(PlayerEngine engine) async {
    final player = await factory(engine);

    await player.init();

    return player;
  }

  Future<void> removeFromCache(PlayerEngine engine) async {
    if (_cache.containsKey(engine)) {
      final player = _cache[engine]!;
      await player.hardDispose(); // 销毁原生
      _cache.remove(engine); // 从缓存删除
    }
  }

  Future<void> disposeAll() async {
    for (final player in _cache.values) {
      await player.hardDispose();
    }

    _cache.clear();
  }
}
