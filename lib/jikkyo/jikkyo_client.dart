import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'jikkyo_channels.dart';
import 'jikkyo_comment.dart';

enum JikkyoState { idle, connecting, connected, error }

class _Thread {
  _Thread(this.id, this.startAt);
  final String id;
  final DateTime? startAt;
}

/// NX-Jikkyo(ニコニコ実況の後継)のコメントWebSocketクライアント。
///
/// 放送中(ACTIVE)のスレッドへ接続し、`chat` を [comments] に流す。
/// 切断時は自動で再接続し、日付が変わってスレッドが替わったら張り直す。
class JikkyoClient {
  JikkyoClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  static const apiBase = 'https://nx-jikkyo.tsukumijima.net/api/v1';
  static const wsBase = 'wss://nx-jikkyo.tsukumijima.net/api/v1';

  final http.Client _http;
  final _comments = StreamController<JikkyoComment>.broadcast();
  final _results = StreamController<String>.broadcast();

  /// 受信したコメント(接続直後の過去ログは `live == false`)。
  Stream<JikkyoComment> get comments => _comments.stream;

  /// 投稿結果などのサーバーからの通知。
  Stream<String> get results => _results.stream;

  final state = ValueNotifier<JikkyoState>(JikkyoState.idle);
  String? lastError;
  String? channelId;

  WebSocket? _ws;
  _Thread? _thread;
  String _ticket = '0x12345678';
  bool _live = false;
  int _gen = 0;

  Future<List<JikkyoChannel>> fetchChannels() async {
    final res = await _http.get(Uri.parse('$apiBase/channels')).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return [
      for (final c in list.cast<Map<String, dynamic>>())
        JikkyoChannel(c['id'] as String, c['name'] as String),
    ];
  }

  Future<_Thread?> _activeThread(String jk) async {
    final res = await _http
        .get(Uri.parse('$apiBase/channels/$jk/threads'))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final list = (body is List ? body : (body['threads'] as List)).cast<Map<String, dynamic>>();
    for (final t in list) {
      if (t['status'] == 'ACTIVE') {
        return _Thread('${t['id']}', DateTime.tryParse('${t['start_at']}'));
      }
    }
    return null;
  }

  /// [jk] (例: `jk1`) のコメントに接続する。接続中のものがあれば切り替える。
  void connect(String jk) {
    disconnect();
    channelId = jk;
    final gen = ++_gen;
    state.value = JikkyoState.connecting;
    unawaited(_run(jk, gen));
  }

  void disconnect() {
    _gen++;
    _ws?.close();
    _ws = null;
    _thread = null;
    channelId = null;
    state.value = JikkyoState.idle;
  }

  Future<void> _run(String jk, int gen) async {
    var attempt = 0;
    while (gen == _gen) {
      Timer? rollover;
      try {
        final th = await _activeThread(jk);
        if (gen != _gen) return;
        if (th == null) throw StateError('放送中のスレッドがありません');

        final ws = await WebSocket.connect('$wsBase/channels/$jk/ws/comment')
            .timeout(const Duration(seconds: 15));
        if (gen != _gen) {
          await ws.close();
          return;
        }
        ws.pingInterval = const Duration(seconds: 30);
        _ws = ws;
        _thread = th;
        _live = false;
        ws.add(jsonEncode([
          {'ping': {'content': 'rs:1'}},
          {'ping': {'content': 'ps:0'}},
          {
            'thread': {
              'thread': th.id,
              'version': '20061206',
              'user_id': 'guest',
              'res_from': -30,
              'with_global': 1,
              'scores': 1,
              'nicoru': 0,
            }
          },
          {'ping': {'content': 'pf:0'}},
          {'ping': {'content': 'rf:1'}},
        ]));
        state.value = JikkyoState.connected;
        lastError = null;
        attempt = 0;

        // 日付替わりでスレッドが変わったら張り直す。
        rollover = Timer.periodic(const Duration(minutes: 3), (_) async {
          try {
            final now = await _activeThread(jk);
            if (gen == _gen && now != null && now.id != th.id) await ws.close();
          } catch (_) {}
        });

        await for (final m in ws) {
          if (gen != _gen) break;
          if (m is String) _handle(m);
        }
      } catch (e) {
        lastError = '$e';
        if (gen == _gen) state.value = JikkyoState.error;
      } finally {
        rollover?.cancel();
        _ws = null;
      }
      if (gen != _gen) return;
      attempt++;
      await Future.delayed(Duration(seconds: math.min(30, 2 * attempt)));
      if (gen == _gen) state.value = JikkyoState.connecting;
    }
  }

  void _handle(String raw) {
    Map<String, dynamic> m;
    try {
      m = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final chat = m['chat'];
    if (chat is Map<String, dynamic>) {
      final c = JikkyoComment.fromChat(chat, live: _live);
      if (c != null && !_comments.isClosed) _comments.add(c);
      return;
    }
    final ping = m['ping'];
    if (ping is Map && ping['content'] == 'pf:0') {
      _live = true; // ここまでが過去ログ
      return;
    }
    final thread = m['thread'];
    if (thread is Map && thread['ticket'] != null) {
      _ticket = '${thread['ticket']}';
      return;
    }
    final result = m['chat_result'];
    if (result is Map) _results.add('投稿結果: status=${result['status']}');
  }

  /// コメントを投稿する。未接続なら false。
  /// 投稿の可否・結果はサーバー側の仕様(ログイン要否など)に依存する。
  bool post(String text, {String mail = '184'}) {
    final ws = _ws;
    final th = _thread;
    if (ws == null || th == null || text.trim().isEmpty) return false;
    final start = th.startAt ?? DateTime.now();
    final vpos = DateTime.now().difference(start).inMilliseconds ~/ 10;
    ws.add(jsonEncode({
      'chat': {
        'thread': th.id,
        'vpos': vpos,
        'mail': mail,
        'ticket': _ticket,
        'user_id': 'guest',
        'premium': 0,
        'content': text,
      }
    }));
    return true;
  }

  void dispose() {
    disconnect();
    _comments.close();
    _results.close();
    state.dispose();
    _http.close();
  }
}
