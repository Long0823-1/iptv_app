import 'dart:ui' show Color;

enum CommentPosition { naka, ue, shita }

/// コメントのコマンド欄(mail)から決まる見た目。ニコニコ動画/実況のコマンド互換。
class CommentStyle {
  const CommentStyle({
    this.color = const Color(0xFFFFFFFF),
    this.sizeScale = 1.0,
    this.position = CommentPosition.naka,
  });

  final Color color;
  final double sizeScale;
  final CommentPosition position;

  static const _colors = <String, int>{
    'white': 0xFFFFFF,
    'red': 0xFF0000,
    'pink': 0xFF8080,
    'orange': 0xFFC000,
    'yellow': 0xFFFF00,
    'green': 0x00FF00,
    'cyan': 0x00FFFF,
    'blue': 0x0000FF,
    'purple': 0xC000FF,
    'black': 0x000000,
    // プレミアム会員色
    'niconicowhite': 0xCCCC99,
    'white2': 0xCCCC99,
    'truered': 0xCC0033,
    'red2': 0xCC0033,
    'passionorange': 0xFF6600,
    'orange2': 0xFF6600,
    'madyellow': 0x999900,
    'yellow2': 0x999900,
    'elementalgreen': 0x00CC66,
    'green2': 0x00CC66,
    'marineblue': 0x33FFFC,
    'blue2': 0x33FFFC,
    'nobleviolet': 0x6633CC,
    'purple2': 0x6633CC,
  };

  static final _hex = RegExp(r'^#([0-9a-fA-F]{6})$');

  static CommentStyle parse(String? mail) {
    var color = const Color(0xFFFFFFFF);
    var size = 1.0;
    var pos = CommentPosition.naka;
    for (final raw in (mail ?? '').split(RegExp(r'\s+'))) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      final lower = t.toLowerCase();
      final named = _colors[lower];
      final hex = _hex.firstMatch(t);
      if (named != null) {
        color = Color(0xFF000000 | named);
      } else if (hex != null) {
        color = Color(0xFF000000 | int.parse(hex.group(1)!, radix: 16));
      } else if (lower == 'big') {
        size = 1.4;
      } else if (lower == 'small') {
        size = 0.75;
      } else if (lower == 'ue') {
        pos = CommentPosition.ue;
      } else if (lower == 'shita') {
        pos = CommentPosition.shita;
      }
    }
    return CommentStyle(color: color, sizeScale: size, position: pos);
  }
}

class JikkyoComment {
  JikkyoComment({
    required this.no,
    required this.text,
    required this.mail,
    required this.userId,
    required this.date,
    this.live = true,
  }) : style = CommentStyle.parse(mail);

  final int no;
  final String text;
  final String mail;
  final String userId;
  final DateTime date;

  /// 接続直後に流れてくる過去ログではなく、リアルタイムのコメントか。
  final bool live;
  final CommentStyle style;

  /// サーバーの `chat` オブジェクトから作る。本文が空のものは null。
  static JikkyoComment? fromChat(Map<String, dynamic> chat, {bool live = true}) {
    final text = (chat['content'] ?? '').toString();
    if (text.trim().isEmpty) return null;
    final sec = (chat['date'] as num?)?.toInt() ?? 0;
    return JikkyoComment(
      no: (chat['no'] as num?)?.toInt() ?? 0,
      text: text,
      mail: (chat['mail'] ?? '').toString(),
      userId: (chat['user_id'] ?? '').toString(),
      date: DateTime.fromMillisecondsSinceEpoch(sec * 1000),
      live: live,
    );
  }
}
