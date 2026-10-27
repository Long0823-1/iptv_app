import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../player_controller.dart';
import 'browser_panel.dart';
import 'player_view.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});
  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PlayerController _pc = PlayerController(widget.state);

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    _pc.init();
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  static final _digits = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.digit0: 0,
    LogicalKeyboardKey.digit1: 1,
    LogicalKeyboardKey.digit2: 2,
    LogicalKeyboardKey.digit3: 3,
    LogicalKeyboardKey.digit4: 4,
    LogicalKeyboardKey.digit5: 5,
    LogicalKeyboardKey.digit6: 6,
    LogicalKeyboardKey.digit7: 7,
    LogicalKeyboardKey.digit8: 8,
    LogicalKeyboardKey.digit9: 9,
    LogicalKeyboardKey.numpad0: 0,
    LogicalKeyboardKey.numpad1: 1,
    LogicalKeyboardKey.numpad2: 2,
    LogicalKeyboardKey.numpad3: 3,
    LogicalKeyboardKey.numpad4: 4,
    LogicalKeyboardKey.numpad5: 5,
    LogicalKeyboardKey.numpad6: 6,
    LogicalKeyboardKey.numpad7: 7,
    LogicalKeyboardKey.numpad8: 8,
    LogicalKeyboardKey.numpad9: 9,
  };

  /// 検索欄やコメント入力欄に文字を打っているときは、ショートカットを効かせない。
  bool get _typing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent || _typing) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final pc = _pc;

    final digit = _digits[k];
    if (digit != null && e is KeyDownEvent) {
      pc.inputDigit(digit);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      if (pc.numberInput.isEmpty) return KeyEventResult.ignored;
      pc.commitNumber();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (pc.numberInput.isNotEmpty) {
        pc.cancelNumber();
      } else if (pc.channelListVisible) {
        pc.toggleChannelList();
      } else if (pc.jikkyo.showPanel) {
        pc.toggleJikkyoPanel();
      } else if (pc.fullscreen) {
        pc.setFullscreen(false);
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    // 押しっぱなしでも連続して効かせたいキー
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.pageUp) {
      pc.zap(-1);
    } else if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.pageDown) {
      pc.zap(1);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      pc.setVolume(pc.volume - 5);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      pc.setVolume(pc.volume + 5);
    } else if (e is! KeyDownEvent) {
      return KeyEventResult.ignored;
    } else if (k == LogicalKeyboardKey.keyF || k == LogicalKeyboardKey.f11) {
      pc.toggleFullscreen();
    } else if (k == LogicalKeyboardKey.keyM) {
      pc.toggleMute();
    } else if (k == LogicalKeyboardKey.keyC) {
      pc.jikkyo.setEnabled(!pc.jikkyo.enabled);
    } else if (k == LogicalKeyboardKey.keyJ) {
      pc.toggleJikkyoPanel();
    } else if (k == LogicalKeyboardKey.keyL) {
      pc.toggleChannelList();
    } else if (k == LogicalKeyboardKey.space) {
      pc.player.playOrPause();
    } else {
      return KeyEventResult.ignored;
    }
    pc.pokeControls();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: Listenable.merge([s, _pc]),
        builder: (context, _) {
          final player = PlayerView(pc: _pc);

          // 全画面: 映像だけを画面いっぱいに表示する。
          if (_pc.fullscreen) {
            return Scaffold(backgroundColor: Colors.black, body: player);
          }

          return LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 900;
            final browser = BrowserPanel(pc: _pc);
            final c = _pc.current;
            return Scaffold(
              appBar: AppBar(
                title: Text(c == null ? 'IPTV' : '${c.number}  ${c.tvgName ?? c.name}'),
                actions: [
                  if (s.loading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  IconButton(icon: const Icon(Icons.refresh), tooltip: '再読み込み', onPressed: s.reload),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    tooltip: '設定',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => SettingsScreen(state: s)),
                    ),
                  ),
                ],
              ),
              body: wide
                  ? Row(children: [
                      Expanded(flex: 5, child: player),
                      Expanded(flex: 4, child: browser),
                    ])
                  : Column(children: [
                      AspectRatio(aspectRatio: 16 / 9, child: player),
                      Expanded(child: browser),
                    ]),
            );
          });
        },
      ),
    );
  }
}
