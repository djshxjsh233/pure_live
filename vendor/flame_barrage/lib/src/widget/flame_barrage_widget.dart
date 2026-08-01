import 'package:flame/game.dart';
import '../atlas/emoji_atlas.dart';
import '../core/barrage_config.dart';
import '../core/barrage_engine.dart';
import 'package:flutter/material.dart';
import '../core/barrage_controller.dart';

class FlameBarrageWidget extends StatefulWidget {
  const FlameBarrageWidget({super.key, required this.config, required this.emojiAtlas, required this.controller});

  final BarrageConfig config;
  final EmojiAtlas emojiAtlas;
  final BarrageController controller;

  @override
  State<FlameBarrageWidget> createState() => _FlameBarrageWidgetState();
}

class _FlameBarrageWidgetState extends State<FlameBarrageWidget> {
  late final BarrageEngine _engine;

  @override
  void initState() {
    super.initState();
    _engine = BarrageEngine(config: widget.config, emojiAtlas: widget.emojiAtlas);
    _initControllerCallbacks();
  }

  @override
  void didUpdateWidget(covariant FlameBarrageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _engine.updateConfig(widget.config);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.detach(_engine);
      _initControllerCallbacks();
    }
  }

  void _initControllerCallbacks() {
    widget.controller.attach(_engine);

    // 去掉 if(mounted) 检查：widget 在全屏/横屏切换时会被销毁重建，
    // 回调总是指向最新创建的 engine，避免重建期间弹幕因 state 失效而被丢弃。
    widget.controller.onAddDanmaku = (item) {
      _engine.pushMessage(item);
    };

    widget.controller.onUpdateOption = (newConfig) {
      _engine.updateConfig(newConfig);
    };

    widget.controller.onPause = () {
      _engine.pause();
    };

    widget.controller.onResume = () {
      _engine.resume();
    };

    widget.controller.onClear = () {
      _engine.clear();
    };
  }

  @override
  void dispose() {
    // 只从 controller 的引擎栈移除自己，不影响仍在渲染的(栈顶)引擎。
    // 这样切全屏时新引擎 attach 到栈顶正常接收弹幕，旧引擎 dispose 仅移除自身。
    widget.controller.detach(_engine);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameWidget(game: _engine);
  }
}
