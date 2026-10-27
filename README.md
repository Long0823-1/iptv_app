# IPTV App

M3U/M3U8 + XMLTV番組表対応のIPTVプレイヤー。Flutter + media_kit(libmpv)で Android / iOS / Windows / macOS を単一コードで対応。

## セットアップ(初回のみ)

```
cd iptv_app
flutter create --platforms=android,ios,windows,macos --org com.example .
flutter pub get
flutter test
flutter run -d windows
```

## プラットフォーム別の設定

- **Android**: `android/app/src/main/AndroidManifest.xml` に `<uses-permission android:name="android.permission.INTERNET"/>`、
  LAN内のhttp配信(例: `http://192.168.x.x`)は `<application android:usesCleartextTraffic="true" ...>`。
- **iOS**: `ios/Runner/Info.plist` に `NSAppTransportSecurity` > `NSAllowsArbitraryLoads` = true と、
  `NSLocalNetworkUsageDescription`(LAN内チューナー利用のため)。ビルドにはMacが必要。
- **macOS**: `macos/Runner/*.entitlements` に `com.apple.security.network.client` = true。
- **Windows**: 追加設定なし(Developer Modeを有効化)。

## キーボードショートカット

| キー | 動作 |
|---|---|
| `F` / `F11` / ダブルクリック | 全画面の切替(`Esc` で解除) |
| `↑` `↓` / `PageUp` `PageDown` | チャンネル切替 |
| `0`〜`9` | チャンネル番号の直接入力(`Enter` で即決、1.8秒で自動決定、`Esc` で取消) |
| `←` `→` | 音量 −5 / +5 |
| `M` | ミュート |
| `Space` | 一時停止/再生 |
| `C` | 実況コメントの表示/非表示 |
| `J` | コメント一覧・投稿パネル(全画面) |
| `L` | チャンネル一覧(全画面) |

## ニコニコ実況(NX-Jikkyo)

公式のニコニコ実況は終了しているため、後継の [NX-Jikkyo](https://nx-jikkyo.tsukumijima.net/) に接続します。

- 局名(tvg-name)から実況チャンネル(jk1 など)を自動判定。誤判定は「実況」タブのプルダウンで手動指定でき、記憶されます
- 流れるコメント(右→左)、`ue` / `shita` の固定表示、`red` `big` `small` `#RRGGBB` などのコマンドに対応
- 不透明度・文字サイズの調整、コメント一覧、投稿(匿名 `184`)
- 接続は放送中スレッドへ。切断時は自動再接続、日付替わりでスレッドが替わったら張り直し
- コメント投稿はサーバー側の仕様(ログイン要否など)に依存し、未検証です

## 機能

- M3U/M3U8読み込み(tvg-id / tvg-chno / tvg-logo / group-title)、HLS単体URLも可
- `url-tvg` から番組表URLを自動取得、XMLTV(.gz対応)
- チャンネル番号順の一覧、グループ絞り込み、↑↓/PageUp/PageDownでザッピング
- 番組表グリッド(縦=時間、横=チャンネル)、現在/次の番組表示
- 全画面(操作パネル・カーソルの自動非表示、全画面用チャンネル一覧)、チャンネル切替バナー
- 番組の開始〜終了時刻を基準にした進捗バー(受信秒数ではない)
- お気に入り、検索(局名・番号・番組名)、前回のチャンネル/音量/画面比率の復元
- 音声切替(主/副音声)、画面比率(標準/拡大/引き伸ばし/16:9/4:3)、オフタイマー(30〜120分)
- 視聴中の再接続(チューナーは同時1接続のため、切替時に前の接続を閉じてから開く)
