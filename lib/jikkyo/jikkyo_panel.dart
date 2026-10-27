import 'package:flutter/material.dart';

import '../util.dart';
import 'jikkyo_client.dart';
import 'jikkyo_controller.dart';

/// 実況コメント一覧・投稿・設定のパネル(通常画面のタブ/全画面の右側に重ねて表示)。
class JikkyoPanel extends StatefulWidget {
  const JikkyoPanel({super.key, required this.controller, this.dark = false});
  final JikkyoController controller;

  /// 映像の上に重ねるときは半透明の暗い背景にする。
  final bool dark;

  @override
  State<JikkyoPanel> createState() => _JikkyoPanelState();
}

class _JikkyoPanelState extends State<JikkyoPanel> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _anonymous = true;

  JikkyoController get jc => widget.controller;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    if (jc.post(t, anonymous: _anonymous)) _text.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([jc, jc.client.state]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final bg = widget.dark ? const Color(0xE6101418) : theme.colorScheme.surface;
        final state = jc.client.state.value;
        final (label, color) = switch (state) {
          JikkyoState.connected => ('接続中', Colors.greenAccent),
          JikkyoState.connecting => ('接続しています…', Colors.amberAccent),
          JikkyoState.error => ('接続エラー(再試行中)', Colors.redAccent),
          JikkyoState.idle => (jc.enabled ? '待機' : 'オフ', Colors.grey),
        };
        final items = jc.recent;
        return Material(
          color: bg,
          child: Column(children: [
            _header(theme, label, color),
            const Divider(height: 1),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        jc.channel == null ? 'このチャンネルに対応する実況がありません' : 'コメントを待っています…',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final c = items[items.length - 1 - i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          child: Text.rich(TextSpan(children: [
                            TextSpan(
                              text: '${fmtTime(c.date)}  ',
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                            TextSpan(text: c.text, style: const TextStyle(fontSize: 13)),
                          ])),
                        );
                      },
                    ),
            ),
            if (jc.notice != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(jc.notice!,
                    style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
              ),
            _composer(),
          ]),
        );
      },
    );
  }

  Widget _header(ThemeData theme, String label, Color color) {
    final channels = jc.allChannels;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
          const Spacer(),
          const Text('表示', style: TextStyle(fontSize: 12)),
          Switch(value: jc.enabled, onChanged: jc.setEnabled),
        ]),
        if (channels.isNotEmpty)
          DropdownButton<String?>(
            isExpanded: true,
            isDense: true,
            value: jc.channel?.id,
            hint: const Text('実況チャンネル(自動)', style: TextStyle(fontSize: 12)),
            items: [
              for (final c in channels)
                DropdownMenuItem(
                  value: c.id,
                  child: Text('${c.id}  ${c.name}', style: const TextStyle(fontSize: 12)),
                ),
            ],
            onChanged: (id) {
              final m = channels.where((c) => c.id == id).firstOrNull;
              jc.assign(m);
            },
          ),
        Row(children: [
          const SizedBox(width: 56, child: Text('不透明度', style: TextStyle(fontSize: 11))),
          Expanded(
            child: Slider(
              value: jc.opacity,
              min: 0.2,
              max: 1,
              onChanged: jc.setOpacity,
            ),
          ),
        ]),
        Row(children: [
          const SizedBox(width: 56, child: Text('文字', style: TextStyle(fontSize: 11))),
          Expanded(
            child: Slider(
              value: jc.fontScale,
              min: 0.6,
              max: 1.8,
              onChanged: jc.setFontScale,
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _composer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 6, 8),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _text,
            focusNode: _focus,
            maxLength: 75,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              counterText: '',
              hintText: 'コメントを入力',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: '匿名(184)',
          child: Checkbox(
            value: _anonymous,
            visualDensity: VisualDensity.compact,
            onChanged: (v) => setState(() => _anonymous = v ?? true),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.send),
          tooltip: '送信',
          onPressed: _send,
        ),
      ]),
    );
  }
}
