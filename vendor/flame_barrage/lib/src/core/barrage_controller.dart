import 'package:flutter/material.dart';

class BarrageController {
  dynamic _engine;
  void Function(dynamic)? _onAddDanmaku;
  void Function(dynamic)? _onUpdateOption;
  void Function()? _onPause;
  void Function()? _onResume;
  void Function()? _onClear;

  bool running = true;
  int _totalEmittedCount = 0;
  final List<dynamic> _pendingBuffer = [];

  dynamic get engine => _engine;

  set onAddDanmaku(void Function(dynamic) callback) => _onAddDanmaku = callback;
  set onUpdateOption(void Function(dynamic) callback) => _onUpdateOption = callback;
  set onPause(void Function() callback) => _onPause = callback;
  set onResume(void Function() callback) => _onResume = callback;
  set onClear(void Function() callback) => _onClear = callback;
  void togglePause() {
    if (running) {
      pause();
    } else {
      resume();
    }
  }

  void attach(dynamic engine) {
    _engine = engine;
    // 重建后 engine 已绑定：把切换重建期间暂存的弹幕补发给新 engine，避免丢失
    if (_pendingBuffer.isNotEmpty) {
      final buf = List<dynamic>.from(_pendingBuffer);
      _pendingBuffer.clear();
      for (final item in buf) {
        _engine?.pushMessage(item);
      }
    }
  }

  void detach() {
    _engine = null;
  }

  void send(dynamic item) {
    _totalEmittedCount++;
    // 直接投递给当前绑定的 engine（由 attach 设置），不再依赖 widget State 的 onAddDanmaku
    // 回调，从而避免全屏/横屏切换重建时回调指向失效 engine 导致弹幕丢失。
    final eng = _engine;
    if (eng != null) {
      eng.pushMessage(item);
    } else {
      // engine 尚未绑定（切换重建中），先缓存，attach 后补发
      if (_pendingBuffer.length < 500) _pendingBuffer.add(item);
    }
    debugPrint('Send barrage item: ${item.content}');
  }

  void updateConfig(dynamic newConfig) {
    _onUpdateOption?.call(newConfig);
  }

  void pause() {
    running = false;
    _onPause?.call();
  }

  void resume() {
    running = true;
    _onResume?.call();
  }

  void clear() {
    _onClear?.call();
  }

  int get totalEmitted => _totalEmittedCount;

  int get pictureCacheCount {
    final currentEngine = _engine;
    if (currentEngine != null) {
      try {
        return currentEngine.activeCacheSize as int;
      } catch (_) {}
    }
    return 0;
  }

  int get poolObjectCount {
    final currentEngine = _engine;
    if (currentEngine != null) {
      try {
        return currentEngine.activePoolSize as int;
      } catch (_) {}
    }
    return 0;
  }
}
