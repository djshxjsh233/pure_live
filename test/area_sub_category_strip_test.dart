import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/modules/area_rooms/widgets/area_sub_category_strip.dart';

void main() {
  testWidgets('strip lists every child and reports the tapped one', (tester) async {
    final children = [
      LiveArea(platform: 'douyin', areaId: '2,1', areaName: '竞技游戏'),
      LiveArea(platform: 'douyin', areaId: '1,1', areaName: '射击游戏'),
      LiveArea(platform: 'douyin', areaId: '3,1', areaName: '单机游戏'),
    ];
    LiveArea? tapped;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AreaSubCategoryStrip(children: children, onSelected: (area) => tapped = area),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('area-sub-category-strip')), findsOneWidget);
    expect(find.text('竞技游戏'), findsOneWidget);
    expect(find.text('射击游戏'), findsOneWidget);
    expect(find.text('单机游戏'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('area-sub-category-2')));
    await tester.pump();

    expect(tapped?.areaId, '3,1');
    expect(tapped?.areaName, '单机游戏');
  });
}
