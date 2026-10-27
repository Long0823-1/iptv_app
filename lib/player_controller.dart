import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show BoxFit;
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'jikkyo/jikkyo_controller.dart';
import 'models.dart';

/// 画面比率の表示モード。
enum AspectMode {
  fit('標準'),
  fill('拡大(切り抜き)'),
  stretch('引き伸ばし'),
  r169('16:9 固定'),
  r43('4:3 固定');

  const AspectMode(this.label);
  final String label;

  BoxFit get boxFit => switch (this) {
        AspectMode.fill => BoxFit.cover,
        AspectMode.stretch => BoxFit.fill,
        _ => BoxFit.contain,
      };

  double? get ratio => switch (this) {
        AspectMode.r169 => 16 / 9,
        AspectMode.r43 => 4 / 3,
        _ => null,
      };
}

bool get isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// 再生・チャンネル操作・全画面・オフタイマーなど、視聴まわりの状態をまとめて持つ。
class PlayerController extends ChangeNotifier {
  PlayerController(this.app) {
    jikkyo = JikkyoController();
    _subs.addAll([
      // ライブ配信は終端に達する/切断されると止まるので、同じチャンネルを開き直す。
      player.stream.completed.listen((done) {
        if (done) _retry('配信が終了しました');
      }),
      player.stream.error.listen((e) {
        // 受信開始直後のAAC/MPEG-2の壊れたフレームは一時的で、その後は正常に再生される。
        // 接続系のエラーだけ再試行する。
        if (_connectionError.hasMatch(e)) _retry(e);
      }),
      player.stream.log.listen((l) {
        if (_transientLog.hasMatch(l.text)) return;
        if (l.level == 'error' || l.level == 'fatal') {
          lastLog = '${l.prefix}: ${l.text.trim()}';
          notifyListeners();
        }
      }),
      player.stream.position.listen((p) {
        if (p > const Duration(seconds: 30) && _retries > 0) _retries = 0;
      }),
    ]);
    app.addListener(_maybeRestore);
  }

  final AppState app;
  late final JikkyoController jikkyo;

  // ライブ(MPEG-TS)の途切れ対策として大きめのバッファを確保する。
  final Player player = Player(
    configuration: const PlayerConfiguration(bufferSize: 128 * 1024 * 1024),
  );
  late final VideoController video = VideoController(player);

  static final _connectionError = RegExp(
    r'Failed to open|HTTP error|Connection|timed out|Failed to recognize|Server returned|Input/output error',
    caseSensitive: false,
  );

  /// ライブ受信の開始直後に出る一時的なデコードエラー/警告(画面には出さない)。
  static final _transientLog = RegExp(
    r'decoding (audio|video)|Invalid frame dimensions|Could not find codec parameters|'
    r'aac:|mpeg2video:|channel element|SBR was found|Reserved bit|Number of bands|'
    r'Invalid mb type|Warning MVs',
    caseSensitive: false,
  );

  final _subs = <StreamSubscription>[];
  Channel? current;
  String? error;
  String? lastLog;

  // --- 表示状態 ---
  bool fullscreen = false;
  bool controlsVisible = true;
  bool bannerVisible = false;
  bool channelListVisible = false;
  AspectMode aspect = AspectMode.fit;
  double volume = 100;
  bool muted = false;
  String numberInput = '';
  DateTime? sleepAt;

  int _retries = 0;
  int _gen = 0;
  bool _opening = false;
  bool _restored = false;
  bool _disposed = false;
  static const _maxRetries = 6;

  Timer? _hideTimer;
  Timer? _bannerTimer;
  Timer? _numTimer;
  Timer? _sleepTimer;
  Timer? _sleepTick;

  Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      volume = p.getDouble('volume') ?? 100;
      muted = p.getBool('muted') ?? false;
      final a = p.getInt('aspect');
      if (a != null && a >= 0 && a < AspectMode.values.length) aspect = AspectMode.values[a];
    } catch (_) {}
    await _configure();
    await player.setVolume(muted ? 0 : volume);
    await jikkyo.init();
    notifyListeners();
    _maybeRestore();
  }

  Future<void> _configure() async {
    final p = player.platform;
    if (p is! NativePlayer) return;
    const props = {
      // 実時間で流れてくるライブTSは、キャッシュ待ちで一時停止させると
      // 数秒ごとに止まって見えるので、停止せず再生し続ける。
      'cache': 'yes',
      'cache-secs': '10',
      'demuxer-readahead-secs': '5',
      'cache-pause': 'no',
      'network-timeout': '30',
      // チューナーは同時1接続(2本目は409)なので、mpv側の自動再接続は使わない。
      'keep-open': 'yes',
      'video-sync': 'audio',
      'framedrop': 'vo',
      'hwdec': 'auto-safe',
    };
    for (final e in props.entries) {
      await p.setProperty(e.key, e.value);
    }
    if (Platform.isWindows) {
      // Windowsは yadif を有効にして自前ビルドした libmpv (windows/libmpv)。
      // 1080iを60pに倍化してインターレース解除する。
      await p.setProperty('hwdec', 'no');
      await p.setProperty('vf', 'lavfi=[yadif=mode=1]');
      return;
    }
    // その他は同梱のlibmpvにFFmpegフィルタが無いので、GPUシェーダで縞を取り除く。
    final shader = await _writeDeinterlaceShader();
    if (shader != null) await p.setProperty('glsl-shaders', shader);
  }

  Future<String?> _writeDeinterlaceShader() async {
    try {
      final f = File('${Directory.systemTemp.path}/iptv_deinterlace.glsl');
      await f.writeAsString(_deinterlaceShader);
      return f.path.replaceAll('\\', '/');
    } catch (_) {
      return null;
    }
  }

  /// 縞(コーミング)が出ている画素だけ上下の行の平均に置き換える適応型デインターレース。
  static const _deinterlaceShader = r'''
//!HOOK MAIN
//!BIND HOOKED
//!DESC comb-adaptive deinterlace

vec4 hook() {
    vec4 c = HOOKED_texOff(vec2(0.0, 0.0));
    vec4 u = HOOKED_texOff(vec2(0.0, -1.0));
    vec4 d = HOOKED_texOff(vec2(0.0, 1.0));
    float m = dot((c.rgb - u.rgb) * (c.rgb - d.rgb), vec3(0.3333));
    float k = smoothstep(0.002, 0.02, m);
    return mix(c, (u + d) * 0.5, k);
}
''';

  /// 起動後、チャンネル一覧が読み込めたら前回のチャンネルを自動で開く(テレビの電源オン)。
  void _maybeRestore() {
    if (_restored || current != null || app.channels.isEmpty) return;
    _restored = true;
    final c = app.lastChannel;
    if (c != null) tune(c);
  }

  // --- チャンネル操作 ---

  void tune(Channel c) {
    _retries = 0;
    current = c;
    error = null;
    lastLog = null;
    channelListVisible = false;
    app.rememberChannel(c);
    jikkyo.onTune(c);
    showBanner();
    notifyListeners();
    _open(c);
  }

  void zap(int delta, {List<Channel>? within}) {
    final list = within ?? app.channels;
    if (list.isEmpty) return;
    final i = current == null ? (delta > 0 ? -1 : 0) : list.indexOf(current!);
    tune(list[(i + delta) % list.length]);
  }

  void inputDigit(int d) {
    if (numberInput.length >= 4) numberInput = '';
    numberInput += '$d';
    notifyListeners();
    _numTimer?.cancel();
    _numTimer = Timer(const Duration(milliseconds: 1800), commitNumber);
  }

  void commitNumber() {
    _numTimer?.cancel();
    final n = int.tryParse(numberInput);
    numberInput = '';
    notifyListeners();
    if (n == null) return;
    final c = app.byNumber(n);
    if (c != null) tune(c);
  }

  void cancelNumber() {
    _numTimer?.cancel();
    numberInput = '';
    notifyListeners();
  }

  void _retry(String reason) {
    final c = current;
    // 切替・再オープン中に出るエラーは無視する。
    if (c == null || _disposed || _opening) return;
    if (_retries >= _maxRetries) {
      error = '再生が止まりました: $reason';
      notifyListeners();
      return;
    }
    _retries++;
    _open(c, wait: Duration(milliseconds: 1000 * _retries));
  }

  /// 前の接続を閉じ、チューナーが解放されるのを待ってから開く。
  /// 連続操作では最後の呼び出しだけが実際にオープンする。
  Future<void> _open(Channel c, {Duration wait = const Duration(milliseconds: 700)}) async {
    final gen = ++_gen;
    _opening = true;
    await player.stop();
    await Future.delayed(wait);
    if (_disposed || gen != _gen) return;
    _opening = false;
    await player.open(Media(c.url));
  }

  // --- 音量・画面 ---

  Future<void> setVolume(double v) async {
    volume = v.clamp(0, 100).toDouble();
    if (volume > 0) muted = false;
    await player.setVolume(muted ? 0 : volume);
    notifyListeners();
    _save((p) async {
      await p.setDouble('volume', volume);
      await p.setBool('muted', muted);
    });
  }

  Future<void> toggleMute() async {
    muted = !muted;
    await player.setVolume(muted ? 0 : volume);
    notifyListeners();
    _save((p) => p.setBool('muted', muted));
  }

  void setAspect(AspectMode m) {
    aspect = m;
    notifyListeners();
    _save((p) => p.setInt('aspect', m.index));
  }

  Future<void> _save(Future<void> Function(SharedPreferences p) f) async {
    try {
      await f(await SharedPreferences.getInstance());
    } catch (_) {}
  }

  // --- 全画面と操作パネル ---

  Future<void> setFullscreen(bool v) async {
    if (fullscreen == v) return;
    fullscreen = v;
    controlsVisible = true;
    channelListVisible = false;
    notifyListeners();
    try {
      if (isDesktop) {
        await windowManager.setFullScreen(v);
      } else {
        await SystemChrome.setEnabledSystemUIMode(
            v ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
        await SystemChrome.setPreferredOrientations(v
            ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
            : DeviceOrientation.values);
      }
    } catch (_) {}
    pokeControls();
  }

  Future<void> toggleFullscreen() => setFullscreen(!fullscreen);

  /// マウス/タッチの操作があったとき。全画面ではしばらくして操作パネルを隠す。
  void pokeControls() {
    if (!controlsVisible) {
      controlsVisible = true;
      notifyListeners();
    }
    _hideTimer?.cancel();
    if (fullscreen) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (_disposed || channelListVisible || jikkyo.showPanel) return;
        controlsVisible = false;
        notifyListeners();
      });
    }
  }

  void toggleControls() {
    if (controlsVisible && fullscreen) {
      _hideTimer?.cancel();
      controlsVisible = false;
      notifyListeners();
    } else {
      pokeControls();
    }
  }

  void toggleChannelList() {
    channelListVisible = !channelListVisible;
    if (channelListVisible) jikkyo.showPanel = false;
    controlsVisible = true;
    notifyListeners();
    pokeControls();
  }

  void toggleJikkyoPanel() {
    jikkyo.togglePanel();
    if (jikkyo.showPanel) channelListVisible = false;
    controlsVisible = true;
    notifyListeners();
    pokeControls();
  }

  void showBanner() {
    bannerVisible = true;
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 5), () {
      if (_disposed) return;
      bannerVisible = false;
      notifyListeners();
    });
  }

  // --- オフタイマー ---

  Duration? get sleepRemaining {
    final t = sleepAt;
    if (t == null) return null;
    final d = t.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  void setSleep(Duration? d) {
    _sleepTimer?.cancel();
    _sleepTick?.cancel();
    if (d == null) {
      sleepAt = null;
      notifyListeners();
      return;
    }
    sleepAt = DateTime.now().add(d);
    _sleepTimer = Timer(d, () async {
      sleepAt = null;
      _sleepTick?.cancel();
      await player.stop();
      current = null;
      if (fullscreen) await setFullscreen(false);
      if (!_disposed) notifyListeners();
    });
    _sleepTick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_disposed) notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    for (final t in [_hideTimer, _bannerTimer, _numTimer, _sleepTimer, _sleepTick]) {
      t?.cancel();
    }
    app.removeListener(_maybeRestore);
    jikkyo.dispose();
    player.dispose();
    super.dispose();
  }
}
