class JikkyoChannel {
  const JikkyoChannel(this.id, this.name);
  final String id; // 例: jk1
  final String name; // 例: NHK総合

  @override
  String toString() => '$id $name';
}

/// 放送局名(M3Uのtvg-name等)から、NX-Jikkyoの実況チャンネルを割り出す。
class JikkyoChannelMap {
  JikkyoChannelMap(this.channels)
      : _byNorm = {for (final c in channels) normalize(c.name): c};

  final List<JikkyoChannel> channels;
  final Map<String, JikkyoChannel> _byNorm;

  /// 放送局名の表記ゆれ → NX-Jikkyoの正式名(正規化後)
  static const _aliases = <String, String>{
    '日テレ': '日本テレビ',
    'NTV': '日本テレビ',
    'テレ朝': 'テレビ朝日',
    'TBS': 'TBSテレビ',
    'テレ東': 'テレビ東京',
    'フジ': 'フジテレビ',
    'CX': 'フジテレビ',
    'Eテレ': 'NHKEテレ',
    'NHK教育': 'NHKEテレ',
    '東京MX': 'TOKYOMX',
    'MX': 'TOKYOMX',
    'NHKBSプレミアム': 'NHKBSプレミアム4K',
    'BSテレ朝': 'BS朝日',
    'BSTBS': 'BS-TBS',
  };

  /// 全角英数→半角、空白除去、大文字化。
  static String normalize(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0xFF01 && r <= 0xFF5E) {
        b.writeCharCode(r - 0xFEE0);
      } else if (r == 0x3000 || r == 0x20 || r == 0x09) {
        continue;
      } else {
        b.writeCharCode(r);
      }
    }
    return b.toString().toUpperCase();
  }

  /// 「011 NHK総合1・東京」→「NHK総合1」。チャンネル番号と「・東京」「(関東)」を除く。
  static String _base(String name) {
    var s = normalize(name);
    s = s.replaceFirst(RegExp(r'^\d{1,4}(?=\D)'), ''); // 先頭のチャンネル番号
    return s.split(RegExp(r'[・(（\[]')).first;
  }

  /// 「011 NHK総合1・東京」→「NHK総合」。末尾のサブチャンネル番号も除いた局名の核。
  static String core(String name) => _base(name).replaceFirst(RegExp(r'\d+$'), '');

  JikkyoChannel? resolve(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    // BS11/BS12のように番号が局名の一部の場合があるので、番号つきも先に照合する。
    final exact = _byNorm[_base(name)] ?? _byNorm[core(name)];
    if (exact != null) return exact;
    final n = core(name);
    if (n.isEmpty) return null;

    for (final e in _aliases.entries) {
      final key = normalize(e.key);
      if (n == key || n.startsWith(key)) {
        final hit = _byNorm[normalize(e.value)];
        if (hit != null) return hit;
      }
    }

    // 前方一致(長い局名を優先)
    JikkyoChannel? best;
    var bestLen = 0;
    for (final e in _byNorm.entries) {
      if (e.key.length < 3) continue;
      if (n.startsWith(e.key) || e.key.startsWith(n)) {
        if (e.key.length > bestLen) {
          best = e.value;
          bestLen = e.key.length;
        }
      }
    }
    return best;
  }
}
