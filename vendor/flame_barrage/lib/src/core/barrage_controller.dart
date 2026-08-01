import 'package:flutter/material.dart';

class BarrageController {
  // 用栈管理多个(可能并存)的弹幕引擎。栈顶 = 最新 attach 且未 detach 的 engine，
  // 即当前正在渲染的引擎。弹幕只投递给栈顶，避免投给已销毁或非渲染的 engine。
  final List<dynamic> _engineStack = [];
  void Function(dynamic)? _onAddDanmaku;
  void Function(dynamic)? _onUpdateOption;
  void Function()? _onPause;
  void Function()? _onResume;
  void Function()? _onClear;

  bool running = true;
  int _totalEmittedCount = 0;
  final List<dynamic> _pendingBuffer = [];

  dynamic get engine => _engineStack.isNotEmpty ? _engineStack.last : null;

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
    if (engine != null && !_engineStack.contains(engine)) {
      _engineStack.add(engine);
    }
    // 新 engine 已绑定：把切换重建期间暂存的弹幕补发给当前(栈顶)引擎，避免丢失
    if (_pendingBuffer.isNotEmpty) {
      final buf = List<dynamic>.from(_pendingBuffer);
      _pendingBuffer.clear();
      for (final item in buf) {
        engine?.pushMessage(item);
      }
    }
  }

  void detach(dynamic engine) {
    // 只移除自己，不影响栈顶(正在渲染的)引擎
    if (engine != null) {
      _engineStack.remove(engine);
    }
  }

  void send(dynamic item) {
    _totalEmittedCount++;
    // 直接投递给栈顶(正在渲染的)引擎，不再依赖 widget State 的 onAddDanmaku 回调，
    // 避免切换重建时投到已销毁或非渲染的 engine 导致弹幕丢失。
    final eng = engine;
    if (eng != null) {
      eng.pushMessage(item);
    } else {
      // 引擎尚未绑定（切换重建中），先缓存，attach 后补发
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
    final currentEngine = engine;
    if (currentEngine != null) {
      try {
        return currentEngine.activeCacheSize as int;
      } catch (_) {}
    }
    return 0;
  }

  int get poolObjectCount {
    final currentEngine = engine;
    if (currentEngine != null) {
      try {
        return currentEngine.activePoolSize as int;
      } catch (_) {}
    }
    return 0;
  }
}
