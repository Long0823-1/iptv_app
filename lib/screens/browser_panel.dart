import 'package:flutter/material.dart';

import '../jikkyo/jikkyo_panel.dart';
import '../models.dart';
import '../player_controller.dart';
import '../util.dart';
import 'epg_grid.dart';

/// チャンネル一覧(検索・お気に入り・グループ絞り込み)/番組表/実況コメントの3タブ。
class BrowserPanel extends StatefulWidget {
  const BrowserPanel({super.key, required this.pc});
  final PlayerController pc;

  @override
  State<BrowserPanel> createState() => _BrowserPanelState();
}

class _BrowserPanelState extends State<BrowserPanel> {
  String? _group;
  bool _favOnly = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final pc = widget.pc;
    final state = pc.app;
    if (state.error != null) {
      return Center(child: Text('読み込みエラー\n${state.error}', textAlign: TextAlign.center));
    }
    if (state.channels.isEmpty) {
      return const Center(child: Text('右上の設定からプレイリストURLを登録してください'));
    }
    final groups = {for (final c in state.channels) c.group ?? '未分類'}.toList();
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final c in state.channels)
        if ((_group == null || (c.group ?? '未分類') == _group) &&
            (!_favOnly || state.isFavorite(c)) &&
            (q.isEmpty ||
                (c.tvgName ?? c.name).toLowerCase().contains(q) ||
                '${c.number}'.contains(q) ||
                (state.nowOn(c)?.title.toLowerCase().contains(q) ?? false)))
          c,
    ];
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        const TabBar(tabs: [Tab(text: 'チャンネル'), Tab(text: '番組表'), Tab(text: '実況')]),
        Expanded(
          child: TabBarView(physics: const NeverScrollableScrollPhysics(), children: [
            _channelList(pc, groups, shown),
            EpgGrid(state: state, channels: shown, onTune: pc.tune),
            JikkyoPanel(controller: pc.jikkyo),
          ]),
        ),
      ]),
    );
  }

  Widget _channelList(PlayerController pc, List<String> groups, List<Channel> shown) {
    final state = pc.app;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        child: TextField(
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 18),
            hintText: '局名・番号・番組名で検索',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: FilterChip(
                avatar: const Icon(Icons.star, size: 16, color: Colors.amber),
                label: const Text('お気に入り'),
                selected: _favOnly,
                onSelected: (v) => setState(() => _favOnly = v),
              ),
            ),
            if (groups.length > 1)
              for (final g in [null, ...groups])
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ChoiceChip(
                    label: Text(g ?? 'すべて'),
                    selected: _group == g,
                    onSelected: (_) => setState(() => _group = g),
                  ),
                ),
          ],
        ),
      ),
      Expanded(
        child: shown.isEmpty
            ? const Center(child: Text('該当するチャンネルがありません'))
            : ListView.builder(
                itemCount: shown.length,
                itemBuilder: (_, i) {
                  final c = shown[i];
                  final now = state.nowOn(c);
                  return ListTile(
                    selected: c == pc.current,
                    leading: SizedBox(
                      width: 40,
                      child: c.logo != null
                          ? Image.network(c.logo!, errorBuilder: (_, __, ___) => _num(c))
                          : _num(c),
                    ),
                    title: Text(c.tvgName ?? c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: now == null
                        ? null
                        : Text('${fmtTime(now.start)} ${now.title}',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: Icon(state.isFavorite(c) ? Icons.star : Icons.star_border,
                          color: state.isFavorite(c) ? Colors.amber : null),
                      tooltip: 'お気に入り',
                      onPressed: () => state.toggleFavorite(c),
                    ),
                    onTap: () => pc.tune(c),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _num(Channel c) => Center(child: Text('${c.number}'));
}
