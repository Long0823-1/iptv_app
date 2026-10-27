import 'package:flutter/material.dart';

import '../app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _playlist = TextEditingController(text: widget.state.playlistUrl);
  late final _epg = TextEditingController(text: widget.state.epgUrl);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
            controller: _playlist,
            decoration: const InputDecoration(
              labelText: 'プレイリストURL (m3u / m3u8)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _epg,
            decoration: const InputDecoration(
              labelText: '番組表URL (XMLTV / .gz) ※空欄ならM3Uヘッダーのurl-tvgを使用',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              widget.state.save(_playlist.text, _epg.text);
              Navigator.of(context).pop();
            },
            child: const Text('保存して読み込み'),
          ),
        ]),
      ),
    );
  }
}
