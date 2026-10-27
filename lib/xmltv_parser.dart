import 'package:xml/xml.dart';

import 'models.dart';

/// XMLTV形式の時刻 `20261027210000 +0900` をパースする。
/// タイムゾーン省略時はUTC扱い(XMLTV仕様)。
DateTime? parseXmltvTime(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})?(\d{2})?(\d{2})?\s*([+-]\d{4})?')
      .firstMatch(s.trim());
  if (m == null) return null;
  int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
  var t = DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6));
  final tz = m.group(7);
  if (tz != null) {
    final sign = tz.startsWith('-') ? -1 : 1;
    final off = Duration(
      hours: int.parse(tz.substring(1, 3)),
      minutes: int.parse(tz.substring(3, 5)),
    );
    t = sign > 0 ? t.subtract(off) : t.add(off);
  }
  return t.toLocal();
}

class Epg {
  const Epg(this.programmes, this.channelNames);

  /// channel id -> 開始時刻順の番組リスト
  final Map<String, List<Programme>> programmes;

  /// channel id -> display-name 一覧(tvg-idが無いM3U向けの名前照合用)
  final Map<String, List<String>> channelNames;

  static const empty = Epg({}, {});

  Programme? nowOn(String channelId, DateTime now) {
    for (final p in programmes[channelId] ?? const <Programme>[]) {
      if (p.isOnAir(now)) return p;
    }
    return null;
  }

  Programme? nextOn(String channelId, DateTime now) {
    for (final p in programmes[channelId] ?? const <Programme>[]) {
      if (p.start.isAfter(now)) return p;
    }
    return null;
  }
}

Epg parseXmltv(String xml) {
  final doc = XmlDocument.parse(xml);
  final tv = doc.rootElement;

  final names = <String, List<String>>{};
  for (final c in tv.findElements('channel')) {
    final id = c.getAttribute('id');
    if (id == null) continue;
    names[id] = [for (final n in c.findElements('display-name')) n.innerText.trim()];
  }

  final byChannel = <String, List<Programme>>{};
  for (final p in tv.findElements('programme')) {
    final id = p.getAttribute('channel');
    final start = parseXmltvTime(p.getAttribute('start'));
    final stop = parseXmltvTime(p.getAttribute('stop'));
    if (id == null || start == null || stop == null) continue;
    byChannel.putIfAbsent(id, () => []).add(Programme(
          channelId: id,
          start: start,
          stop: stop,
          title: p.getElement('title')?.innerText.trim() ?? '',
          description: p.getElement('desc')?.innerText.trim(),
          category: p.getElement('category')?.innerText.trim(),
        ));
  }
  for (final l in byChannel.values) {
    l.sort((a, b) => a.start.compareTo(b.start));
  }
  return Epg(byChannel, names);
}
