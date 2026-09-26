import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/douyin/douyin_site.dart';

Map<String, dynamic> _partition(String id, int type, String title) => {'id_str': id, 'type': type, 'title': title};

Map<String, dynamic> _node(String id, int type, String title, {List<dynamic> subs = const []}) => <String, dynamic>{
  'partition': _partition(id, type, title),
  'sub_partition': subs,
};

/// Shape mirrors the live page: 聊天/音乐 are leaves, 游戏 owns the only third
/// level (竞技游戏/射击游戏 > individual titles).
List<Map<String, dynamic>> _catalog() => [
  _node('101', 4, '聊天'),
  _node(
    '103',
    4,
    '游戏',
    subs: [
      _node('2', 1, '竞技游戏', subs: [_node('1010235', 1, '王者万象棋'), _node('1010014', 1, '英雄联盟')]),
      _node('1', 1, '射击游戏', subs: [_node('1010003', 1, 'CSGO')]),
    ],
  ),
  _node('102', 4, '音乐'),
];

void main() {
  test('keeps top-level partitions and nests the game subtree three levels deep', () {
    final categories = DouyinSite.parseCategories(_catalog());

    expect(categories.map((c) => c.name), ['聊天', '游戏', '音乐']);
    expect(categories.map((c) => c.id), ['101,4', '103,4', '102,4']);

    final chat = categories.first;
    expect(chat.children, isEmpty);

    final game = categories[1];
    expect(game.children.map((a) => a.areaName), ['竞技游戏', '射击游戏']);

    final competitive = game.children.first;
    expect(competitive.areaId, '2,1');
    expect(competitive.areaType, '103,4');
    expect(competitive.typeName, '游戏');
    expect(competitive.platform, 'douyin');
    expect(competitive.areaPic, '');
    expect(competitive.children!.map((a) => a.areaName), ['王者万象棋', '英雄联盟']);

    final lol = competitive.children![1];
    expect(lol.areaId, '1010014,1');
    expect(lol.areaType, '2,1');
    expect(lol.typeName, '竞技游戏');
    expect(lol.children, isNull);

    final shooter = game.children[1];
    expect(shooter.areaId, '1,1');
    expect(shooter.children!.single.areaId, '1010003,1');
  });

  test('decodes the escaped page payload into the same tree', () {
    final payload = json.encode({'pathname': '/', 'categoryData': _catalog()});
    final page = '<html><script>window.__RENDER_DATA__ = ${payload.replaceAll('"', r'\"')};</script></html>';

    final extracted = DouyinSite().extractCategoryDataJson(page);
    expect(extracted, isNotEmpty);

    final decoded = json.decode(extracted);
    final categories = DouyinSite.parseCategories((decoded as Map)['categoryData']);
    expect(categories, hasLength(3));
    expect(categories[1].children.first.children!.last.areaName, '英雄联盟');
  });

  test('ignores malformed payloads instead of throwing', () {
    expect(DouyinSite.parseCategories(null), isEmpty);
    expect(DouyinSite.parseCategories('not-a-list'), isEmpty);
    expect(
      DouyinSite.parseCategories([
        'not-a-map',
        {'sub_partition': const []},
        _node('9', 4, '空分区'),
        {
          'partition': _partition('7', 4, '坏子类'),
          'sub_partition': [
            'bad',
            {'partition': 'bad'},
            _node('8', 1, '好子类', subs: ['bad', _node('1010001', 1, '叶子')]),
          ],
        },
      ]).map((c) => c.name),
      ['空分区', '坏子类'],
    );
  });

  test('a partition without a third level has no children list to render', () {
    final categories = DouyinSite.parseCategories([
      _node('105', 4, '舞蹈', subs: [_node('9', 1, '宅舞')]),
    ]);
    expect(categories.single.children.single.children, isNull);
  });
}
