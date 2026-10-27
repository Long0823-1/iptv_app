import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/m3u_parser.dart';
import 'package:iptv_app/xmltv_parser.dart';

const _m3u = '''#EXTM3U url-tvg="http://example.com/epg.xml"
#EXTINF:-1 tvg-id="a" tvg-chno="011" tvg-name="NHK" group-title="G",011 NHK
http://example.com/a.ts
#EXTINF:-1 tvg-id="b" group-title="G",Foo
http://example.com/b.m3u8
''';

void main() {
  test('M3Uのチャンネルと属性', () {
    final ch = parseM3u(_m3u);
    expect(ch.length, 2);
    expect(ch[0].number, 11);
    expect(ch[0].tvgId, 'a');
    expect(ch[0].group, 'G');
    expect(ch[1].number, 1); // 自動採番
    expect(parseM3uEpgUrls(_m3u), ['http://example.com/epg.xml']);
  });

  test('HLSプレイリスト単体は1チャンネル', () {
    final ch = parseM3u('#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nseg.ts\n#EXT-X-ENDLIST',
        sourceUrl: 'http://example.com/live.m3u8');
    expect(ch.length, 1);
    expect(ch.single.url, 'http://example.com/live.m3u8');
  });

  test('XMLTVの時刻とタイムゾーン', () {
    final t = parseXmltvTime('20261027210000 +0900')!;
    expect(t.toUtc(), DateTime.utc(2026, 10, 27, 12));
  });

  test('XMLTV番組の現在/次', () {
    final epg = parseXmltv('''<tv>
<channel id="a"><display-name>NHK</display-name></channel>
<programme start="20261027200000 +0900" stop="20261027210000 +0900" channel="a"><title>ニュース</title></programme>
<programme start="20261027210000 +0900" stop="20261027220000 +0900" channel="a"><title>ドラマ</title></programme>
</tv>''');
    final now = DateTime.utc(2026, 10, 27, 11, 30); // 20:30 JST
    expect(epg.nowOn('a', now)!.title, 'ニュース');
    expect(epg.nextOn('a', now)!.title, 'ドラマ');
  });
}
