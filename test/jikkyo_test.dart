import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/jikkyo/jikkyo_channels.dart';
import 'package:iptv_app/jikkyo/jikkyo_client.dart';
import 'package:iptv_app/jikkyo/jikkyo_comment.dart';

const _channels = [
  JikkyoChannel('jk1', 'NHK総合'),
  JikkyoChannel('jk2', 'NHK Eテレ'),
  JikkyoChannel('jk4', '日本テレビ'),
  JikkyoChannel('jk5', 'テレビ朝日'),
  JikkyoChannel('jk6', 'TBSテレビ'),
  JikkyoChannel('jk7', 'テレビ東京'),
  JikkyoChannel('jk8', 'フジテレビ'),
  JikkyoChannel('jk9', 'TOKYO MX'),
  JikkyoChannel('jk101', 'NHK BS'),
  JikkyoChannel('jk103', 'NHK BSプレミアム4K'),
  JikkyoChannel('jk141', 'BS日テレ'),
  JikkyoChannel('jk151', 'BS朝日'),
  JikkyoChannel('jk161', 'BS-TBS'),
  JikkyoChannel('jk181', 'BSフジ'),
  JikkyoChannel('jk211', 'BS11'),
];

void main() {
  group('コメントのコマンド', () {
    test('色・位置・サイズ', () {
      final s = CommentStyle.parse('184 red ue big');
      expect(s.color, const Color(0xFFFF0000));
      expect(s.position, CommentPosition.ue);
      expect(s.sizeScale, 1.4);
    });

    test('指定なしは白・流れる・標準', () {
      final s = CommentStyle.parse('184');
      expect(s.color, const Color(0xFFFFFFFF));
      expect(s.position, CommentPosition.naka);
      expect(s.sizeScale, 1.0);
    });

    test('16進カラーとshita/small', () {
      final s = CommentStyle.parse('#00ff80 shita small');
      expect(s.color, const Color(0xFF00FF80));
      expect(s.position, CommentPosition.shita);
      expect(s.sizeScale, 0.75);
    });

    test('chatオブジェクトのパースと空コメントの除外', () {
      final c = JikkyoComment.fromChat({
        'no': 9980,
        'date': 1793085999,
        'mail': '184 pink',
        'user_id': 'nicolive:a:xxx',
        'content': 'ブライト系',
      });
      expect(c, isNotNull);
      expect(c!.text, 'ブライト系');
      expect(c.no, 9980);
      expect(c.style.color, const Color(0xFFFF8080));
      expect(JikkyoComment.fromChat({'content': '  '}), isNull);
    });
  });

  group('局名 → 実況チャンネル', () {
    final map = JikkyoChannelMap(_channels);
    String? jk(String? n) => map.resolve(n)?.id;

    test('実際のプレイリストの局名', () {
      expect(jk('ＮＨＫ総合１・東京'), 'jk1');
      expect(jk('ＮＨＫ総合２・東京'), 'jk1');
      expect(jk('日テレ１'), 'jk4');
      expect(jk('テレビ朝日'), 'jk5');
      expect(jk('011 ＮＨＫ総合１・東京'), 'jk1');
    });

    test('表記ゆれ', () {
      expect(jk('Ｅテレ１東京'), 'jk2');
      expect(jk('ＴＢＳ１'), 'jk6');
      expect(jk('テレビ東京１'), 'jk7');
      expect(jk('フジテレビ'), 'jk8');
      expect(jk('ＴＯＫＹＯ　ＭＸ１'), 'jk9');
    });

    test('BS局', () {
      expect(jk('ＢＳ日テレ'), 'jk141');
      expect(jk('ＢＳ朝日１'), 'jk151');
      expect(jk('ＢＳ－ＴＢＳ'), 'jk161');
      expect(jk('ＢＳ１１'), 'jk211');
    });

    test('不明な局はnull', () {
      expect(jk('ショップチャンネル'), isNull);
      expect(jk(''), isNull);
      expect(jk(null), isNull);
    });
  });

  // 実サーバーに接続するテスト。`JIKKYO_LIVE=1 flutter test` のときだけ実行する。
  test('実況サーバーからコメントを受信できる (live)', () async {
    final client = JikkyoClient();
    final got = <JikkyoComment>[];
    final sub = client.comments.listen(got.add);
    client.connect('jk1');
    final end = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(end) && got.length < 5) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    final state = client.state.value;
    final err = client.lastError;
    await sub.cancel();
    client.dispose();
    // ignore: avoid_print
    print('state=$state received=${got.length} history=${got.where((c) => !c.live).length} err=$err');
    // ignore: avoid_print
    for (final c in got.take(3)) {
      // ignore: avoid_print
      print('  #${c.no} [${c.mail}] ${c.text}');
    }
    expect(state, JikkyoState.connected);
    expect(got, isNotEmpty);
  }, skip: Platform.environment['JIKKYO_LIVE'] != '1' ? 'JIKKYO_LIVE=1 のときのみ実行' : false);
}
