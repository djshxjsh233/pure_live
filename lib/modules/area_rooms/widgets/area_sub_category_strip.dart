import 'package:pure_live/common/index.dart';

const double areaSubCategoryStripHeight = 56;

/// Next-level selector for platforms whose directory is deeper than one hop.
///
/// Douyin's game partition nests 游戏 > 竞技游戏 > 英雄联盟. The current node's
/// room list stays the page body while this strip pushes the next level, so
/// "all game rooms" and a single game's rooms are each one tap apart — the same
/// shape the website uses, without a second round trip per level.
class AreaSubCategoryStrip extends StatelessWidget {
  const AreaSubCategoryStrip({super.key, required this.children, required this.onSelected});

  final List<LiveArea> children;
  final ValueChanged<LiveArea> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: areaSubCategoryStripHeight,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(overscroll: false, scrollbars: false),
        child: ListView.separated(
          key: const ValueKey('area-sub-category-strip'),
          scrollDirection: Axis.horizontal,
          physics: const PureLiveBoundedScrollPhysics(),
          clipBehavior: Clip.hardEdge,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final child = children[index];
            final name = child.areaName?.trim() ?? '';
            return Center(
              child: ActionChip(
                key: ValueKey('area-sub-category-$index'),
                label: Text(name.isEmpty ? i18n('unnamed_area') : name),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                side: BorderSide(color: theme.colorScheme.outlineVariant),
                onPressed: () => onSelected(child),
              ),
            );
          },
        ),
      ),
    );
  }
}
