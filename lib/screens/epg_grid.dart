import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../util.dart';

const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

/// ジャンル(XMLTVのcategory)から番組セルの色を決める。
Color genreColor(String? category) {
  final c = category ?? '';
  if (c.contains('ニュース') || c.contains('報道')) return const Color(0xFFCFE2F3);
  if (c.contains('スポーツ')) return const Color(0xFFCDE8C8);
  if (c.contains('ドラマ')) return const Color(0xFFF8D7B5);
  if (c.contains('アニメ') || c.contains('特撮')) return const Color(0xFFF5CBDD);
  if (c.contains('バラエティ')) return const Color(0xFFF7F0B0);
  if (c.contains('映画')) return const Color(0xFFD9CCF0);
  if (c.contains('音楽')) return const Color(0xFFF3C6C6);
  if (c.contains('情報') || c.contains('ワイド')) return const Color(0xFFD6EFEF);
  if (c.contains('ドキュメンタリー') || c.contains('教養')) return const Color(0xFFE3EBC8);
  return const Color(0xFFE8E8E8);
}

/// 日本のテレビ番組表風グリッド。縦=時間(5時〜翌5時)、横=チャンネル。
class EpgGrid extends StatefulWidget {
  const EpgGrid({super.key, required this.state, required this.channels, required this.onTune});
  final AppState state;
  final List<Channel> channels;
  final ValueChanged<Channel> onTune;

  @override
  State<EpgGrid> createState() => _EpgGridState();
}

class _EpgGridState extends State<EpgGrid> {
  static const double colW = 150, hourH = 170, headH = 44, timeW = 36;
  static const int dayStartHour = 5, spanHours = 24, dayCount = 7;
  static const Color gridLine = Color(0xFF9AA0A6);

  final _hHead = ScrollController();
  final _hBody = ScrollController();
  final _v = ScrollController();
  bool _syncing = false;

  int _dayOffset = 0;
  Programme? _selected;
  Channel? _selectedChannel;

  /// 放送日の起点。深夜0〜5時は前日扱い。
  DateTime get _baseDay {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day);
    return now.hour < dayStartHour ? d.subtract(const Duration(days: 1)) : d;
  }

  DateTime get _dayStart =>
      _baseDay.add(Duration(days: _dayOffset, hours: dayStartHour));

  @override
  void initState() {
    super.initState();
    _hBody.addListener(() => _sync(_hBody, _hHead));
    _hHead.addListener(() => _sync(_hHead, _hBody));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNow());
  }

  @override
  void dispose() {
    _hHead.dispose();
    _hBody.dispose();
    _v.dispose();
    super.dispose();
  }

  void _sync(ScrollController from, ScrollController to) {
    if (_syncing || !from.hasClients || !to.hasClients) return;
    _syncing = true;
    to.jumpTo(from.offset.clamp(0.0, to.position.maxScrollExtent));
    _syncing = false;
  }

  void _scrollToNow() {
    if (!_v.hasClients || _dayOffset != 0) return;
    final hours = DateTime.now().difference(_dayStart).inMinutes / 60;
    _v.jumpTo(((hours - 0.5) * hourH).clamp(0.0, _v.position.maxScrollExtent));
  }

  void _select(Channel c, Programme p) {
    setState(() {
      _selected = p;
      _selectedChannel = c;
    });
  }

  @override
  Widget build(BuildContext context) {
    final channels = widget.channels;
    final dayStart = _dayStart;
    final dayEnd = dayStart.add(const Duration(hours: spanHours));
    final now = DateTime.now();
    double y(DateTime t) => t.difference(dayStart).inMinutes / 60 * hourH;

    final cells = <Widget>[];
    for (var i = 0; i < channels.length; i++) {
      final c = channels[i];
      final id = widget.state.epgIdFor(c);
      final list = (id == null ? null : widget.state.epg.programmes[id]) ?? const <Programme>[];
      for (final p in list) {
        if (!p.stop.isAfter(dayStart) || !p.start.isBefore(dayEnd)) continue;
        final top = y(p.start.isBefore(dayStart) ? dayStart : p.start);
        final bottom = y(p.stop.isAfter(dayEnd) ? dayEnd : p.stop);
        cells.add(Positioned(
          left: i * colW,
          top: top,
          width: colW,
          height: bottom - top,
          child: _Cell(
            programme: p,
            selected: identical(p, _selected),
            onAir: p.isOnAir(now),
            onTap: () => _select(c, p),
            onDoubleTap: () => widget.onTune(c),
          ),
        ));
      }
    }

    final showNow = _dayOffset == 0 && now.isAfter(dayStart) && now.isBefore(dayEnd);
    const bodyHeight = spanHours * hourH;

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      }),
      child: Column(children: [
        _topPanel(),
        Row(children: [
          const SizedBox(width: timeW, height: headH, child: ColoredBox(color: Color(0xFF3A3F47))),
          Expanded(
            child: SizedBox(
              height: headH,
              child: SingleChildScrollView(
                controller: _hHead,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(children: [
                  for (final c in channels) _header(c),
                ]),
              ),
            ),
          ),
        ]),
        Expanded(
          child: SingleChildScrollView(
            controller: _v,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _timeColumn(dayStart),
              Expanded(
                child: SingleChildScrollView(
                  controller: _hBody,
                  scrollDirection: Axis.horizontal,
                  child: Container(
                    width: channels.length * colW,
                    height: bodyHeight,
                    color: Colors.white,
                    child: Stack(children: [
                      for (var h = 1; h < spanHours; h++)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: h * hourH,
                          child: const Divider(height: 1, thickness: 1, color: gridLine),
                        ),
                      ...cells,
                      if (showNow)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: y(now),
                          child: Container(height: 2, color: Colors.redAccent),
                        ),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _topPanel() {
    final base = _baseDay;
    final p = _selected;
    final c = _selectedChannel;
    return Container(
      color: const Color(0xFF23272E),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 34,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var i = 0; i < dayCount; i++)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(_dayLabel(base.add(Duration(days: i)))),
                  selected: _dayOffset == i,
                  onSelected: (_) => setState(() {
                    _dayOffset = i;
                    _selected = null;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (i == 0) {
                        _scrollToNow();
                      } else if (_v.hasClients) {
                        _v.jumpTo(0);
                      }
                    });
                  }),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        if (p == null)
          const Text('番組を選択すると詳細が表示されます(ダブルタップで視聴)',
              style: TextStyle(color: Colors.white54, fontSize: 12))
        else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  '${c?.name ?? ''}  ${_dayLabel(p.start)} ${fmtTime(p.start)}-${fmtTime(p.stop)}'
                  '${p.category == null ? '' : '  [${p.category}]'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (p.description != null && p.description!.isNotEmpty)
                  Text(p.description!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ]),
            ),
            const SizedBox(width: 8),
            if (c != null)
              FilledButton.icon(
                onPressed: () => widget.onTune(c),
                icon: const Icon(Icons.play_arrow),
                label: const Text('視聴'),
              ),
          ]),
      ]),
    );
  }

  Widget _header(Channel c) {
    return InkWell(
      onTap: () => widget.onTune(c),
      child: Container(
        width: colW,
        height: headH,
        decoration: const BoxDecoration(
          color: Color(0xFFF4F4F4),
          border: Border(left: BorderSide(color: gridLine), bottom: BorderSide(color: gridLine)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          Text('${c.number}',
              style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(c.tvgName ?? c.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    );
  }

  Widget _timeColumn(DateTime dayStart) {
    return SizedBox(
      width: timeW,
      child: Column(children: [
        for (var h = 0; h < spanHours; h++)
          Container(
            height: hourH,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 4),
            decoration: const BoxDecoration(
              color: Color(0xFFE6E0F2),
              border: Border(top: BorderSide(color: gridLine)),
            ),
            child: Text('${dayStart.add(Duration(hours: h)).hour}',
                style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
      ]),
    );
  }

  String _dayLabel(DateTime d) =>
      '${d.month}/${d.day}(${_weekdays[d.weekday - 1]})';
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.programme,
    required this.selected,
    required this.onAir,
    required this.onTap,
    required this.onDoubleTap,
  });
  final Programme programme;
  final bool selected;
  final bool onAir;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final p = programme;
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Container(
        decoration: BoxDecoration(
          color: genreColor(p.category),
          border: selected
              ? Border.all(color: Colors.deepOrange, width: 3)
              : const Border(
                  left: BorderSide(color: _EpgGridState.gridLine),
                  top: BorderSide(color: _EpgGridState.gridLine),
                ),
        ),
        padding: const EdgeInsets.fromLTRB(3, 2, 3, 0),
        // セルの高さに収まる行数だけ描画する(はみ出し警告を出さない)。
        child: LayoutBuilder(builder: (context, box) {
          final lines = ((box.maxHeight - 2) / 14).floor().clamp(1, 200);
          return ClipRect(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(color: Colors.black87, fontSize: 12, height: 1.15),
                children: [
                  TextSpan(
                    text: '${p.start.minute}  ',
                    style: TextStyle(
                        color: onAir ? Colors.red : Colors.black54, fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: p.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (p.description != null && p.description!.isNotEmpty)
                    TextSpan(
                      text: '\n${p.description}',
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                ],
              ),
              maxLines: lines,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }),
      ),
    );
  }
}
