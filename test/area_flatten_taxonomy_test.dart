import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/modules/areas/areas_list_controller.dart';

class _Site extends LiveSite {
  _Site(this.catalog);
  final List<LiveCategory> catalog;

  @override
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async => catalog;
}

class _Controller extends AreasListController {
  _Controller(_Site source, super.site);
  final errors = <Object>[];

  @override
  bool get usesDesktopPagination => false;

  @override
  Future<bool> checkNetworkBeforeRequest() async => true;

  @override
  void handleError(Object error, {bool showPageError = false}) => errors.add(error);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('douyin grid keeps top-level rows and carries the game subtree for drill-down', () async {
    final leaves = [
      LiveArea(platform: 'douyin', areaId: '1010014,1', areaName: '英雄联盟', typeName: '竞技游戏', areaType: '2,1'),
    ];
    final source = _Site([
      LiveCategory(id: '101,4', name: '聊天', children: const []),
      LiveCategory(
        id: '103,4',
        name: '游戏',
        children: [
          LiveArea(
            platform: 'douyin',
            areaId: '2,1',
            areaName: '竞技游戏',
            typeName: '游戏',
            areaType: '103,4',
            children: leaves,
          ),
        ],
      ),
      LiveCategory(id: '102,4', name: '音乐', children: const []),
    ]);
    final controller = _Controller(source, Site(id: Sites.douyinSite, name: '抖音', logo: '', liveSite: source));
    addTearDown(controller.onClose);

    await controller.loadData();

    expect(controller.errors, isEmpty);
    expect(controller.list.map((a) => a.areaName), ['聊天', '游戏', '音乐']);

    final game = controller.list[1];
    expect(game.areaId, '103,4');
    expect(game.areaType, '103,4');
    expect(game.typeName, '游戏');
    expect(game.areaPic, '');
    expect(game.children!.single.areaName, '竞技游戏');
    expect(game.children!.single.areaType, '103,4');
    expect(game.children!.single.children!.single.areaId, '1010014,1');

    // Second-level rows are navigation targets, not grid rows.
    expect(controller.list.where((a) => a.areaId == '2,1'), isEmpty);
    expect(controller.list.first.children, isNull);
    expect(controller.list.last.children, isNull);
  });

  test('a top-level partition without sub-partitions stays a plain room entry', () async {
    final source = _Site([LiveCategory(id: '101,4', name: '聊天', children: const [])]);
    final controller = _Controller(source, Site(id: Sites.douyinSite, name: '抖音', logo: '', liveSite: source));
    addTearDown(controller.onClose);

    await controller.loadData();

    expect(controller.list, hasLength(1));
    expect(controller.list.single.areaName, '聊天');
    expect(controller.list.single.areaId, '101,4');
    expect(controller.list.single.children, isNull);
  });
}
