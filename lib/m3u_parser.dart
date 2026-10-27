import 'models.dart';

final _attrRe = RegExp(r'([\w-]+)="([^"]*)"');

/// M3U / M3U8 (IPTV拡張) をパースする。
///
/// - `#EXTINF` 付きの通常のIPTVプレイリスト
/// - `#EXT-X-` を含むHLSメディア/マスタープレイリストそのもの(単一チャンネル扱い)
List<Channel> parseM3u(String text, {String? sourceUrl}) {
  final lines = text.replaceAll('\r', '').split('\n');

  const hlsTags = ['#EXT-X-TARGETDURATION', '#EXT-X-STREAM-INF', '#EXT-X-MEDIA-SEQUENCE'];
  if (sourceUrl != null && lines.any((l) => hlsTags.any(l.startsWith))) {
    return [Channel(name: Uri.parse(sourceUrl).pathSegments.last, url: sourceUrl)];
  }

  final channels = <Channel>[];
  String? name, tvgId, tvgName, logo, group;
  int? number;
  String? vlcGroup;

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    if (line.startsWith('#EXTINF')) {
      final comma = line.indexOf(',');
      final head = comma >= 0 ? line.substring(0, comma) : line;
      name = comma >= 0 ? line.substring(comma + 1).trim() : null;
      final attrs = {
        for (final m in _attrRe.allMatches(head)) m.group(1)!.toLowerCase(): m.group(2)!,
      };
      tvgId = _nonEmpty(attrs['tvg-id']);
      tvgName = _nonEmpty(attrs['tvg-name']);
      logo = _nonEmpty(attrs['tvg-logo']);
      group = _nonEmpty(attrs['group-title']);
      number = int.tryParse(attrs['tvg-chno'] ?? attrs['channel-number'] ?? '');
    } else if (line.startsWith('#EXTGRP:')) {
      vlcGroup = line.substring(8).trim();
    } else if (line.startsWith('#')) {
      continue;
    } else if (name != null || tvgName != null) {
      channels.add(Channel(
        name: _nonEmpty(name) ?? tvgName ?? line,
        url: line,
        tvgId: tvgId,
        tvgName: tvgName,
        logo: logo,
        group: group ?? vlcGroup,
        number: number,
      ));
      name = tvgId = tvgName = logo = group = vlcGroup = null;
      number = null;
    }
  }

  return assignNumbers(channels);
}

/// `#EXTM3U url-tvg="..." x-tvg-url="..."` から番組表(XMLTV)のURLを取り出す。
/// カンマ区切りで複数指定される場合がある。
List<String> parseM3uEpgUrls(String text) {
  final first = text.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  if (!first.startsWith('#EXTM3U')) return const [];
  final attrs = {
    for (final m in _attrRe.allMatches(first)) m.group(1)!.toLowerCase(): m.group(2)!,
  };
  final v = attrs['url-tvg'] ?? attrs['x-tvg-url'] ?? '';
  return [for (final u in v.split(',')) if (u.trim().isNotEmpty) u.trim()];
}

/// 番号未指定のチャンネルに、既存番号と衝突しない連番を振る。
List<Channel> assignNumbers(List<Channel> channels) {
  final used = {for (final c in channels) if (c.number != null) c.number!};
  var next = 1;
  return [
    for (final c in channels)
      if (c.number != null)
        c
      else
        () {
          while (used.contains(next)) {
            next++;
          }
          used.add(next);
          return c.withNumber(next);
        }(),
  ];
}

String? _nonEmpty(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
