import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'jikkyo_channels.dart';
import 'jikkyo_client.dart';
import 'jikkyo_comment.dart';

/// ニコニコ実況(NX-Jikkyo)モード全体の状態。
class JikkyoController extends ChangeNotifier {
  JikkyoController({JikkyoClient? client}) : client = client ?? JikkyoClient() {
    _commentSub = this.client.comments.listen(_onComment);
    _resultSub = this.client.results.listen((r) {
      notice = r;
      _notifySoon();
    });
    this.client.state.addListener(_notifySoon);
  }

  final JikkyoClient client;

  bool enabled = true;
  bool showPanel = false;
  double opacity = 0.9;
  double fontScale = 1.0;

  JikkyoChannelMap? map;
  JikkyoChannel? channel;
  String? notice;
  final recent = <JikkyoComment>[];
  static const _maxRecent = 300;

  Channel? _tuned;
  final Map<String, String> _overrides = {};
  StreamSubscription<JikkyoComment>? _commentSub;
  StreamSubscription<String>? _resultSub;
  Timer? _throttle;

  List<JikkyoChannel> get allChannels => map?.channels ?? const [];

  Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      enabled = p.getBool('jk_enabled') ?? true;
      opacity = p.getDouble('jk_opacity') ?? 0.9;
      fontScale = p.getDouble('jk_font') ?? 1.0;
      final raw = p.getString('jk_overrides');
      if (raw != null) {
        _overrides.addAll((jsonDecode(raw) as Map).cast<String, String>());
      }
    } catch (_) {}
    try {
      map = JikkyoChannelMap(await client.fetchChannels());
    } catch (e) {
      notice = '実況チャンネル一覧を取得できません: $e';
    }
    notifyListeners();
    final t = _tuned;
    if (t != null) onTune(t);
  }

  String _key(Channel c) => c.tvgId ?? c.name;

  /// 視聴チャンネルが変わったとき。対応する実況チャンネルへ接続を切り替える。
  void onTune(Channel c) {
    _tuned = c;
    final m = map;
    if (m == null) return;
    final override = _overrides[_key(c)];
    final jk = override != null
        ? m.channels.where((x) => x.id == override).firstOrNull
        : m.resolve(c.tvgName ?? c.name);
    if (jk?.id != channel?.id) {
      recent.clear();
      notice = null;
    }
    channel = jk;
    if (jk != null && enabled) {
      if (client.channelId != jk.id) client.connect(jk.id);
    } else {
      client.disconnect();
    }
    notifyListeners();
  }

  /// 現在のチャンネルに、手動で実況チャンネルを割り当てる(null で自動判定に戻す)。
  Future<void> assign(JikkyoChannel? jk) async {
    final t = _tuned;
    if (t == null) return;
    if (jk == null) {
      _overrides.remove(_key(t));
    } else {
      _overrides[_key(t)] = jk.id;
    }
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('jk_overrides', jsonEncode(_overrides));
    } catch (_) {}
    client.disconnect();
    onTune(t);
  }

  Future<void> setEnabled(bool v) async {
    enabled = v;
    final t = _tuned;
    if (v && t != null) {
      onTune(t);
    } else if (!v) {
      client.disconnect();
    }
    notifyListeners();
    await _save((p) => p.setBool('jk_enabled', v));
  }

  Future<void> setOpacity(double v) async {
    opacity = v;
    notifyListeners();
    await _save((p) => p.setDouble('jk_opacity', v));
  }

  Future<void> setFontScale(double v) async {
    fontScale = v;
    notifyListeners();
    await _save((p) => p.setDouble('jk_font', v));
  }

  void togglePanel() {
    showPanel = !showPanel;
    notifyListeners();
  }

  /// コメントを投稿する。送信できたら true(受理されたかはサーバー次第)。
  bool post(String text, {bool anonymous = true}) {
    final ok = client.post(text, mail: anonymous ? '184' : '');
    notice = ok ? '送信しました' : '未接続のため送信できません';
    notifyListeners();
    return ok;
  }

  Future<void> _save(Future<void> Function(SharedPreferences p) f) async {
    try {
      await f(await SharedPreferences.getInstance());
    } catch (_) {}
  }

  void _onComment(JikkyoComment c) {
    recent.add(c);
    if (recent.length > _maxRecent) recent.removeRange(0, recent.length - _maxRecent);
    _notifySoon();
  }

  /// コメントは秒間に何十件も来るので、再描画は最大で1秒に4回に間引く。
  void _notifySoon() {
    if (_throttle?.isActive ?? false) return;
    _throttle = Timer(const Duration(milliseconds: 250), notifyListeners);
  }

  @override
  void dispose() {
    _throttle?.cancel();
    _commentSub?.cancel();
    _resultSub?.cancel();
    client.state.removeListener(_notifySoon);
    client.dispose();
    super.dispose();
  }
}
