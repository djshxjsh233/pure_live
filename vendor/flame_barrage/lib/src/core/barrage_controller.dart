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
    // 重建后的 engine 已绑定：把暂停/重建期间暂存的弹幕补发，避免横屏全屏切换丢弹幕
    if (_pendingBuffer.isNotEmpty) {
      final buf = List<dynamic>.from(_pendingBuffer);
      _pendingBuffer.clear();
      for (final item in buf) {
        _onAddDanmaku?.call(item);
      }
    }
  }

  void detach() {
    _engine = null;
  }

  void send(dynamic item) {
    if (!running) {
      // 全屏/横屏切换等引擎暂停/重建期间先缓存，attach 后补发
      if (_pendingBuffer.length < 500) _pendingBuffer.add(item);
      return;
    }
    _totalEmittedCount++;
    debugPrint('Send barrage item: ${item.content}');
    _onAddDanmaku?.call(item);
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
