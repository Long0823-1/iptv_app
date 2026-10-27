import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'm3u_parser.dart';
import 'models.dart';
import 'xmltv_parser.dart';

class AppState extends ChangeNotifier {
  String playlistUrl = '';
  String epgUrl = ''; // 空ならM3Uヘッダーの url-tvg を使う

  List<Channel> channels = [];
  Epg epg = Epg.empty;
  bool loading = false;
  String? error;

  /// お気に入りチャンネル(キーは [channelKey])。
  final Set<String> favorites = {};

  /// 最後に視聴したチャンネルのキー。起動時に復元する。
  String? lastKey;

  static String channelKey(Channel c) => c.tvgId ?? c.name;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    playlistUrl = p.getString('playlistUrl') ?? '';
    epgUrl = p.getString('epgUrl') ?? '';
    favorites
      ..clear()
      ..addAll(p.getStringList('favorites') ?? const []);
    lastKey = p.getString('lastChannel');
    if (playlistUrl.isNotEmpty) await reload();
    notifyListeners();
  }

  bool isFavorite(Channel c) => favorites.contains(channelKey(c));

  Future<void> toggleFavorite(Channel c) async {
    final k = channelKey(c);
    if (!favorites.remove(k)) favorites.add(k);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setStringList('favorites', favorites.toList());
  }

  Channel? get lastChannel {
    final k = lastKey;
    if (k == null) return null;
    for (final c in channels) {
      if (channelKey(c) == k) return c;
    }
    return null;
  }

  Future<void> rememberChannel(Channel c) async {
    lastKey = channelKey(c);
    final p = await SharedPreferences.getInstance();
    await p.setString('lastChannel', lastKey!);
  }

  /// 番号(tvg-chno または連番)でチャンネルを探す。
  Channel? byNumber(int n) {
    for (final c in channels) {
      if (c.number == n) return c;
    }
    return null;
  }

  Future<void> save(String playlist, String epgOverride) async {
    playlistUrl = playlist.trim();
    epgUrl = epgOverride.trim();
    final p = await SharedPreferences.getInstance();
    await p.setString('playlistUrl', playlistUrl);
    await p.setString('epgUrl', epgUrl);
    await reload();
  }

  Future<void> reload() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final text = await _fetchText(playlistUrl);
      channels = parseM3u(text, sourceUrl: playlistUrl);
      final epgTarget = epgUrl.isNotEmpty
          ? epgUrl
          : (parseM3uEpgUrls(text).firstOrNull ?? '');
      epg = epgTarget.isEmpty ? Epg.empty : parseXmltv(await _fetchText(epgTarget));
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// M3U側の tvg-id、無ければ tvg-name / 表示名でEPGのチャンネルを照合する。
  String? epgIdFor(Channel c) {
    if (c.tvgId != null && epg.programmes.containsKey(c.tvgId)) return c.tvgId;
    final names = {c.name, if (c.tvgName != null) c.tvgName!};
    for (final e in epg.channelNames.entries) {
      if (e.value.any(names.contains)) return e.key;
    }
    return null;
  }

  Programme? nowOn(Channel c) {
    final id = epgIdFor(c);
    return id == null ? null : epg.nowOn(id, DateTime.now());
  }

  Programme? nextOn(Channel c) {
    final id = epgIdFor(c);
    return id == null ? null : epg.nextOn(id, DateTime.now());
  }

  Future<String> _fetchText(String url) async {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}: $url');
    var bytes = res.bodyBytes;
    if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      bytes = Uint8List.fromList(gzip.decode(bytes));
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
