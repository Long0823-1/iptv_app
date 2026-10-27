import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app_state.dart';
import '../jikkyo/comment_overlay.dart';
import '../jikkyo/jikkyo_panel.dart';
import '../models.dart';
import '../player_controller.dart';
import '../util.dart';

/// 映像・実況コメント・チャンネルバナー・操作パネルを重ねた再生画面。
/// 通常表示でも全画面でも同じウィジェットを使う。
class PlayerView extends StatelessWidget {
  const PlayerView({super.key, required this.pc});
  final PlayerController pc;

  AppState get app => pc.app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([pc, pc.jikkyo, app]),
      builder: (context, _) {
        final ch = pc.current;
        final fs = pc.fullscreen;
        final show = !fs || pc.controlsVisible;
        // 通常画面では切替直後だけ、全画面では操作パネルと一緒にバナーを出す。
        final showBanner = ch != null && (pc.bannerVisible || (fs && pc.controlsVisible));
        return MouseRegion(
          cursor: (fs && !pc.controlsVisible) ? SystemMouseCursors.none : MouseCursor.defer,
          onHover: (_) => pc.pokeControls(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: pc.toggleControls,
            onDoubleTap: pc.toggleFullscreen,
            child: Stack(fit: StackFit.expand, children: [
              const ColoredBox(color: Colors.black),
              if (ch == null)
                const Center(child: Text('チャンネルを選択してください'))
              else
                Video(
                  controller: pc.video,
                  // 標準コントロール(受信秒数のシークバー)は使わない。
                  controls: NoVideoControls,
                  fit: pc.aspect.boxFit,
                  aspectRatio: pc.aspect.ratio,
                ),
              if (ch != null && pc.jikkyo.enabled)
                CommentOverlay(
                  comments: pc.jikkyo.client.comments,
                  opacity: pc.jikkyo.opacity,
                  fontScale: pc.jikkyo.fontScale,
                  // バナー/操作パネルの文字とコメントが重ならないよう、その分の段を空ける。
                  avoidTop: showBanner ? 110 : 0,
                  avoidBottom: show ? 100 : 0,
                ),
              if (ch != null)
                StreamBuilder<bool>(
                  stream: pc.player.stream.buffering,
                  initialData: false,
                  builder: (_, s) => s.data == true
                      ? const Center(child: CircularProgressIndicator())
                      : const SizedBox.shrink(),
                ),
              if (pc.error != null) Center(child: _Notice(pc.error!)),
              if (pc.lastLog != null)
                Positioned(
                  left: 6,
                  top: 6,
                  right: 6,
                  child: Text(pc.lastLog!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 11)),
                ),
              if (showBanner)
                Positioned(top: 0, left: 0, right: 0, child: _Banner(pc: pc, channel: ch)),
              if (pc.numberInput.isNotEmpty)
                Positioned(top: 70, right: 24, child: _NumberInput(pc.numberInput)),
              if (ch != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedOpacity(
                    opacity: show ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(ignoring: !show, child: _Controls(pc: pc)),
                  ),
                ),
              if (fs && pc.channelListVisible)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: 360,
                  child: _FsChannelList(pc: pc),
                ),
              if (fs && pc.jikkyo.showPanel)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: 380,
                  child: JikkyoPanel(controller: pc.jikkyo, dark: true),
                ),
            ]),
          ),
        );
      },
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.black87,
        padding: const EdgeInsets.all(12),
        child: Text(text, textAlign: TextAlign.center),
      );
}

class _NumberInput extends StatelessWidget {
  const _NumberInput(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white54),
        ),
        child: Text(text.padRight(3, '_'),
            style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold, letterSpacing: 6)),
      );
}

/// チャンネル切替時/操作時に出る、局名と放送中の番組の帯。
class _Banner extends StatelessWidget {
  const _Banner({required this.pc, required this.channel});
  final PlayerController pc;
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final now = pc.app.nowOn(channel);
    final next = pc.app.nextOn(channel);
    final jk = pc.jikkyo.channel;
    // ほぼ不透明にして、背後を流れるコメントが透けて文字が二重に見えないようにする。
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      color: const Color(0xF0000000),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${channel.number}',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.amber)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(channel.tvgName ?? channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          if (jk != null) ...[
            const SizedBox(width: 10),
            Text('実況 ${jk.id}', style: const TextStyle(fontSize: 12, color: Colors.white60)),
          ],
        ]),
        if (now != null) ...[
          const SizedBox(height: 2),
          Text('${fmtTime(now.start)}-${fmtTime(now.stop)}  ${now.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15)),
        ],
        if (next != null)
          Text('次: ${fmtTime(next.start)}  ${next.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ]),
    );
  }
}

/// 下部の操作パネル: 番組の進捗(放送時間基準)・チャンネル/音量・各種機能。
class _Controls extends StatelessWidget {
  const _Controls({required this.pc});
  final PlayerController pc;

  @override
  Widget build(BuildContext context) {
    final ch = pc.current!;
    final fs = pc.fullscreen;
    final now = pc.app.nowOn(ch);
    final jc = pc.jikkyo;
    final remain = pc.sleepRemaining;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      color: const Color(0xF0000000),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (now != null) _Progress(programme: now),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _btn(Icons.skip_previous, '前のチャンネル', () => pc.zap(-1)),
            StreamBuilder<bool>(
              stream: pc.player.stream.playing,
              initialData: pc.player.state.playing,
              builder: (_, s) => _btn(
                s.data == true ? Icons.pause : Icons.play_arrow,
                s.data == true ? '一時停止' : '再生',
                pc.player.playOrPause,
              ),
            ),
            _btn(Icons.skip_next, '次のチャンネル', () => pc.zap(1)),
            _btn(pc.muted || pc.volume == 0 ? Icons.volume_off : Icons.volume_up, 'ミュート',
                pc.toggleMute),
            SizedBox(
              width: 110,
              child: Slider(
                value: pc.muted ? 0 : pc.volume,
                min: 0,
                max: 100,
                onChanged: pc.setVolume,
              ),
            ),
            const SizedBox(width: 8),
            _btn(
              pc.app.isFavorite(ch) ? Icons.star : Icons.star_border,
              'お気に入り',
              () => pc.app.toggleFavorite(ch),
              color: pc.app.isFavorite(ch) ? Colors.amber : null,
            ),
            _btn(
              jc.enabled ? Icons.comment : Icons.comments_disabled,
              jc.enabled ? '実況コメントを隠す (C)' : '実況コメントを表示 (C)',
              () => jc.setEnabled(!jc.enabled),
              color: jc.enabled ? Colors.lightBlueAccent : null,
            ),
            if (fs)
              _btn(Icons.forum, 'コメント一覧・投稿 (J)', pc.toggleJikkyoPanel,
                  color: jc.showPanel ? Colors.lightBlueAccent : null),
            _AudioMenu(pc: pc),
            _AspectMenu(pc: pc),
            _SleepMenu(pc: pc, remaining: remain),
            if (fs)
              _btn(Icons.list, 'チャンネル一覧 (L)', pc.toggleChannelList,
                  color: pc.channelListVisible ? Colors.lightBlueAccent : null),
            _btn(fs ? Icons.fullscreen_exit : Icons.fullscreen, fs ? '全画面を終了 (Esc)' : '全画面 (F)',
                pc.toggleFullscreen),
          ]),
        ),
      ]),
    );
  }

  Widget _btn(IconData icon, String tip, VoidCallback onTap, {Color? color}) => IconButton(
        icon: Icon(icon, color: color ?? Colors.white),
        tooltip: tip,
        iconSize: 22,
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
      );
}

/// 受信秒数ではなく、番組の開始〜終了時刻を基準にした進捗バー。
class _Progress extends StatelessWidget {
  const _Progress({required this.programme});
  final Programme programme;

  @override
  Widget build(BuildContext context) {
    final p = programme;
    final now = DateTime.now();
    final total = p.stop.difference(p.start).inSeconds;
    final done = now.difference(p.start).inSeconds.clamp(0, total);
    final remain = p.stop.difference(now);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(children: [
        Text(fmtTime(p.start), style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 8),
        Expanded(child: LinearProgressIndicator(value: total == 0 ? 0 : done / total, minHeight: 4)),
        const SizedBox(width: 8),
        Text(fmtTime(p.stop), style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 8),
        Text('残り${remain.isNegative ? 0 : remain.inMinutes}分',
            style: const TextStyle(fontSize: 12, color: Colors.white60)),
      ]),
    );
  }
}

class _AudioMenu extends StatelessWidget {
  const _AudioMenu({required this.pc});
  final PlayerController pc;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Tracks>(
      stream: pc.player.stream.tracks,
      initialData: pc.player.state.tracks,
      builder: (context, snap) {
        final tracks = [
          for (final t in snap.data?.audio ?? const <AudioTrack>[])
            if (t.id != 'auto' && t.id != 'no') t,
        ];
        return StreamBuilder<Track>(
          stream: pc.player.stream.track,
          initialData: pc.player.state.track,
          builder: (context, cur) {
            final selected = cur.data?.audio;
            return PopupMenuButton<AudioTrack>(
              tooltip: '音声切替(主音声/副音声)',
              enabled: tracks.length > 1,
              icon: Icon(Icons.audiotrack, color: tracks.length > 1 ? Colors.white : Colors.white30),
              onSelected: pc.player.setAudioTrack,
              itemBuilder: (_) => [
                for (var i = 0; i < tracks.length; i++)
                  CheckedPopupMenuItem(
                    value: tracks[i],
                    checked: tracks[i].id == selected?.id,
                    child: Text(_audioLabel(tracks[i], i)),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  static String _audioLabel(AudioTrack t, int i) {
    final parts = [
      if (t.title != null && t.title!.isNotEmpty) t.title!,
      if (t.language != null && t.language!.isNotEmpty) t.language!,
      if (t.channels != null) t.channels!,
    ];
    return '音声${i + 1}${parts.isEmpty ? '' : '  ${parts.join(' / ')}'}';
  }
}

class _AspectMenu extends StatelessWidget {
  const _AspectMenu({required this.pc});
  final PlayerController pc;

  @override
  Widget build(BuildContext context) => PopupMenuButton<AspectMode>(
        tooltip: '画面比率',
        icon: const Icon(Icons.aspect_ratio, color: Colors.white),
        onSelected: pc.setAspect,
        itemBuilder: (_) => [
          for (final m in AspectMode.values)
            CheckedPopupMenuItem(value: m, checked: m == pc.aspect, child: Text(m.label)),
        ],
      );
}

class _SleepMenu extends StatelessWidget {
  const _SleepMenu({required this.pc, required this.remaining});
  final PlayerController pc;
  final Duration? remaining;

  @override
  Widget build(BuildContext context) {
    final on = remaining != null;
    return PopupMenuButton<int>(
      tooltip: on ? 'オフタイマー(残り${fmtDuration(remaining!)})' : 'オフタイマー',
      icon: Icon(on ? Icons.bedtime : Icons.bedtime_outlined,
          color: on ? Colors.lightBlueAccent : Colors.white),
      onSelected: (m) => pc.setSleep(m == 0 ? null : Duration(minutes: m)),
      itemBuilder: (_) => [
        for (final m in const [30, 60, 90, 120])
          PopupMenuItem(value: m, child: Text('$m分後に切る')),
        if (on) const PopupMenuItem(value: 0, child: Text('タイマーを解除')),
      ],
    );
  }
}

/// 全画面中に右から出すチャンネル一覧(お気に入りの絞り込み付き)。
class _FsChannelList extends StatefulWidget {
  const _FsChannelList({required this.pc});
  final PlayerController pc;

  @override
  State<_FsChannelList> createState() => _FsChannelListState();
}

class _FsChannelListState extends State<_FsChannelList> {
  bool _favOnly = false;

  @override
  Widget build(BuildContext context) {
    final pc = widget.pc;
    final list = [
      for (final c in pc.app.channels)
        if (!_favOnly || pc.app.isFavorite(c)) c,
    ];
    return Material(
      color: const Color(0xE6101418),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            const Text('チャンネル', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            FilterChip(
              label: const Text('★お気に入り'),
              selected: _favOnly,
              onSelected: (v) => setState(() => _favOnly = v),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final c = list[i];
              final now = pc.app.nowOn(c);
              return ListTile(
                dense: true,
                selected: c == pc.current,
                leading: Text('${c.number}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
                title: Text(c.tvgName ?? c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: now == null
                    ? null
                    : Text('${fmtTime(now.start)} ${now.title}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: pc.app.isFavorite(c) ? const Icon(Icons.star, size: 16, color: Colors.amber) : null,
                onTap: () => pc.tune(c),
              );
            },
          ),
        ),
      ]),
    );
  }
}
