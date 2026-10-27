import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'jikkyo_comment.dart';

class _Fly {
  _Fly({
    required this.fill,
    required this.stroke,
    required this.lane,
    required this.position,
    required this.startUs,
    required this.durationUs,
  });

  final TextPainter fill;
  final TextPainter stroke;
  final int lane;
  final CommentPosition position;
  final int startUs;
  final int durationUs;

  double get width => fill.width;
  double get height => fill.height;
}

/// ニコニコ実況風に、コメントを画面上へ流す(右→左)/上・下に固定表示するオーバーレイ。
class CommentOverlay extends StatefulWidget {
  const CommentOverlay({
    super.key,
    required this.comments,
    this.opacity = 0.9,
    this.fontScale = 1.0,
    this.flySeconds = 6.0,
    this.avoidTop = 0,
    this.avoidBottom = 0,
  });

  final Stream<JikkyoComment> comments;
  final double opacity;
  final double fontScale;

  /// 上端/下端のこの高さ(px)は、新しく流すコメントの段として使わない
  /// (チャンネルバナーや操作パネルの文字とコメントが重ならないようにする)。
  final double avoidTop;
  final double avoidBottom;

  /// 右端から左端まで流れ切るのに掛ける秒数。
  final double flySeconds;

  @override
  State<CommentOverlay> createState() => _CommentOverlayState();
}

class _CommentOverlayState extends State<CommentOverlay> with SingleTickerProviderStateMixin {
  static const _maxItems = 120;
  static const _fixedSeconds = 3.5;

  final _items = <_Fly>[];
  final _clock = Stopwatch()..start();
  final _repaint = _Repaint();
  late final Ticker _ticker;
  StreamSubscription<JikkyoComment>? _sub;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _tick());
    _sub = widget.comments.listen(_onComment);
  }

  @override
  void didUpdateWidget(CommentOverlay old) {
    super.didUpdateWidget(old);
    if (old.comments != widget.comments) {
      _sub?.cancel();
      _items.clear();
      _sub = widget.comments.listen(_onComment);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  int get _nowUs => _clock.elapsedMicroseconds;

  double get _fontSize => (_size.height * 0.052 * widget.fontScale).clamp(14.0, 72.0);

  double get _laneHeight => _fontSize * 1.25;

  void _tick() {
    final now = _nowUs;
    _items.removeWhere((f) => now - f.startUs > f.durationUs);
    if (_items.isEmpty) _ticker.stop();
    _repaint.poke();
  }

  void _onComment(JikkyoComment c) {
    if (!c.live || _size.isEmpty || _items.length >= _maxItems) return;
    final text = c.text.replaceAll(RegExp(r'[\r\n]+'), ' ');
    final fs = _fontSize * c.style.sizeScale;

    TextPainter paint(TextStyle s) => TextPainter(
          text: TextSpan(text: text, style: s),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();

    final base = TextStyle(fontSize: fs, fontWeight: FontWeight.w800, height: 1.0);
    final fill = paint(base.copyWith(color: c.style.color));
    final stroke = paint(base.copyWith(
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (fs / 9).clamp(2.0, 6.0)
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xCC000000),
    ));

    final pos = c.style.position;
    final lane = _pickLane(pos, fill.width);
    final durationUs =
        ((pos == CommentPosition.naka ? widget.flySeconds : _fixedSeconds) * 1e6).round();
    _items.add(_Fly(
      fill: fill,
      stroke: stroke,
      lane: lane,
      position: pos,
      startUs: _nowUs,
      durationUs: durationUs,
    ));
    if (!_ticker.isActive) _ticker.start();
  }

  double get _topPad => _size.height * 0.03;

  int get _laneCount {
    final usable = _size.height * 0.90 - _topPad - widget.avoidBottom;
    return (usable / _laneHeight).floor().clamp(1, 40);
  }

  /// 上のバナーを避けるため、最初に使う段。
  int get _firstLane {
    if (widget.avoidTop <= 0) return 0;
    final k = ((widget.avoidTop - _topPad) / _laneHeight).ceil();
    return k.clamp(0, _laneCount - 1);
  }

  /// 重ならないレーンを選ぶ。空きが無ければ、最も余裕のあるレーンに重ねる。
  int _pickLane(CommentPosition pos, double width) {
    final now = _nowUs;
    final n = _laneCount;
    final first = _firstLane;
    if (pos != CommentPosition.naka) {
      final busy = <int>{
        for (final f in _items)
          if (f.position == pos) f.lane,
      };
      for (var i = pos == CommentPosition.ue ? first : 0; i < n; i++) {
        if (!busy.contains(i)) return i;
      }
      return pos == CommentPosition.ue ? first : 0;
    }

    // 各レーンで、最後に入ってきたコメントの右端(画面右端からの余白)を調べる。
    final tail = List<double>.filled(n, double.infinity);
    for (final f in _items) {
      if (f.position != CommentPosition.naka || f.lane >= n) continue;
      final p = ((now - f.startUs) / f.durationUs).clamp(0.0, 1.0);
      final x = _size.width - p * (_size.width + f.width);
      final rightEdge = x + f.width;
      final gap = _size.width - rightEdge; // 大きいほど空いている
      if (gap < tail[f.lane]) tail[f.lane] = gap;
    }
    var best = first;
    var bestGap = -double.infinity;
    for (var i = first; i < n; i++) {
      final gap = tail[i] == double.infinity ? double.maxFinite : tail[i];
      if (gap > _fontSize * 1.5) return i; // 十分に空いている最初のレーン
      if (gap > bestGap) {
        bestGap = gap;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        if (size != _size) {
          _size = size;
          _items.clear();
        }
        // 映像の外(隣のパネル)へコメントがはみ出さないよう、描画範囲で切る。
        return ClipRect(
          child: Opacity(
            opacity: widget.opacity.clamp(0.0, 1.0),
            child: RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: _FlyPainter(
                  items: _items,
                  nowUs: () => _nowUs,
                  laneHeight: _laneHeight,
                  repaint: _repaint,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _Repaint extends ChangeNotifier {
  void poke() => notifyListeners();
}

class _FlyPainter extends CustomPainter {
  _FlyPainter({
    required this.items,
    required this.nowUs,
    required this.laneHeight,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final List<_Fly> items;
  final int Function() nowUs;
  final double laneHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final now = nowUs();
    final topPad = size.height * 0.03;
    final bottomPad = size.height * 0.10; // 下のコントロールに被りにくくする
    for (final f in items) {
      final age = now - f.startUs;
      if (age < 0 || age > f.durationUs) continue;
      late final Offset at;
      switch (f.position) {
        case CommentPosition.naka:
          final p = age / f.durationUs;
          at = Offset(size.width - p * (size.width + f.width), topPad + f.lane * laneHeight);
        case CommentPosition.ue:
          at = Offset((size.width - f.width) / 2, topPad + f.lane * laneHeight);
        case CommentPosition.shita:
          at = Offset((size.width - f.width) / 2,
              size.height - bottomPad - (f.lane + 1) * laneHeight);
      }
      f.stroke.paint(canvas, at);
      f.fill.paint(canvas, at);
    }
  }

  @override
  bool shouldRepaint(_FlyPainter old) => true;
}
