import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/jikkyo/comment_overlay.dart';
import 'package:iptv_app/jikkyo/jikkyo_comment.dart';
import 'package:iptv_app/jikkyo/jikkyo_controller.dart';
import 'package:iptv_app/jikkyo/jikkyo_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

JikkyoComment _c(int no, String text, {String mail = '184', bool live = true}) => JikkyoComment(
      no: no,
      text: text,
      mail: mail,
      userId: 'u$no',
      date: DateTime(2026, 10, 27, 20, 0),
      live: live,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('流れる/上固定/下固定のコメントを描画してもエラーにならない', (tester) async {
    final ctrl = StreamController<JikkyoComment>.broadcast();
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 800,
        height: 450,
        child: CommentOverlay(comments: ctrl.stream),
      ),
    ));

    ctrl.add(_c(1, 'こんにちは'));
    ctrl.add(_c(2, '上に固定', mail: '184 ue red'));
    ctrl.add(_c(3, '下に固定', mail: '184 shita big cyan'));
    ctrl.add(_c(4, '過去ログは流さない', live: false));
    for (var i = 0; i < 40; i++) {
      ctrl.add(_c(10 + i, 'wwww' * (1 + i % 5)));
    }
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);

    // サイズ変更・不透明度変更でも落ちない
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 400,
        height: 300,
        child: CommentOverlay(comments: ctrl.stream, opacity: 0.5, fontScale: 1.5),
      ),
    ));
    ctrl.add(_c(100, 'リサイズ後'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await ctrl.close();
  });

  testWidgets('実況パネルが描画でき、設定を変更できる', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final jc = JikkyoController();
    jc.recent.addAll([_c(1, '一つ目'), _c(2, '二つ目')]);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: SizedBox(width: 380, height: 600, child: JikkyoPanel(controller: jc))),
    ));
    expect(find.textContaining('一つ目', findRichText: true), findsOneWidget);
    expect(find.textContaining('二つ目', findRichText: true), findsOneWidget);
    expect(find.text('コメントを入力'), findsOneWidget);

    await jc.setEnabled(false);
    await jc.setOpacity(0.5);
    await jc.setFontScale(1.4);
    await tester.pump();
    expect(jc.enabled, isFalse);
    expect(jc.opacity, 0.5);
    expect(tester.takeException(), isNull);

    // 未接続での投稿は失敗として通知される
    expect(jc.post('テスト'), isFalse);
    expect(jc.notice, contains('未接続'));
    jc.dispose();
  });
}
