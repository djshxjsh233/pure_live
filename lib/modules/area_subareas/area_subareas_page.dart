import 'package:pure_live/common/index.dart';
import 'package:waterfall_flow/waterfall_flow.dart';
import 'package:pure_live/modules/areas/widgets/area_card.dart';

/// 分类子级页：展示某个二级分类下的三级分类（如"竞技游戏"下的具体游戏）
/// 复用 AreaCard 呈现三级网格，点击三级分类进入房间页。
class AreaSubAreasPage extends StatelessWidget {
  final Site site;
  final LiveArea category;

  const AreaSubAreasPage({super.key, required this.site, required this.category});

  @override
  Widget build(BuildContext context) {
    final List<LiveArea> children = category.children ?? [];
    return Scaffold(
      appBar: AppBar(title: Text(category.areaName ?? '')),
      body: LayoutBuilder(
        builder: (context, constraint) {
          final width = constraint.maxWidth;
          final crossAxisCount = width > 1280 ? 9 : (width > 960 ? 7 : (width > 640 ? 5 : 3));
          return WaterfallFlow.builder(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 80),
            gridDelegate: SliverWaterfallFlowDelegateWithFixedCrossAxisCount(
              lastChildLayoutTypeBuilder: (index) => LastChildLayoutType.none,
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: SettingsService.to.theme.crossAxisSpacing.v,
              mainAxisSpacing: SettingsService.to.theme.mainAxisSpacing.v,
            ),
            itemCount: children.length,
            itemBuilder: (context, index) => AreaCard(category: children[index]),
          );
        },
      ),
    );
  }
}