import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:waterfall_flow/waterfall_flow.dart';
import 'package:pure_live/modules/areas/widgets/area_card.dart';
import 'package:pure_live/modules/areas/areas_list_controller.dart';

class AreaGridView extends StatefulWidget {
  final String tag;
  const AreaGridView(this.tag, {super.key});
  AreasListController get controller => Get.find<AreasListController>(tag: tag);

  bool get isDouyin => tag == Sites.douyinSite;

  @override
  State<AreaGridView> createState() => _AreaGridViewState();
}

class _AreaGridViewState extends State<AreaGridView> with TickerProviderStateMixin {
  TabController? _tabController;
  Worker? _listWorker;

  AreasListController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _listWorker = ever(widget.controller.categories, (_) => _createTabController());
    _createTabController();
    widget.controller.tabIndex.addListener(_handleExternalIndexChange);
  }

  void _createTabController() {
    final list = widget.controller.categories;
    if (list.isEmpty) return;

    if (_tabController != null && _tabController!.length == list.length) {
      return;
    }

    if (_tabController != null) {
      _tabController!.removeListener(_handleInternalTabChange);
      _tabController!.dispose();
    }

    int initialIndex = widget.controller.tabIndex.value;
    if (initialIndex >= list.length) initialIndex = 0;

    _tabController = TabController(length: list.length, vsync: this, initialIndex: initialIndex);
    _tabController!.addListener(_handleInternalTabChange);

    if (mounted) setState(() {});
  }

  void _handleInternalTabChange() {
    if (_tabController == null || _tabController!.indexIsChanging) return;
    if (widget.controller.tabIndex.value != _tabController!.index) {
      final idx = _tabController!.index;
      // 抖音：切换顶级分类 → 重置chips并加载直播间
      if (widget.isDouyin) {
        controller.switchDouyinTop(idx);
      } else {
        controller.tabIndex.value = idx;
        if (Get.width > 680) {
          controller.currentPage = 1;
        }
        controller.loadData();
      }
    }
  }

  void _handleExternalIndexChange() {
    if (_tabController == null) return;
    final targetIndex = widget.controller.tabIndex.value;
    if (_tabController!.index != targetIndex && targetIndex < _tabController!.length) {
      _tabController!.animateTo(targetIndex);
    }
  }

  @override
  void dispose() {
    widget.controller.tabIndex.removeListener(_handleExternalIndexChange);
    _listWorker?.dispose();
    if (_tabController != null) {
      _tabController!.removeListener(_handleInternalTabChange);
      _tabController!.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ==================== 抖音：浏览器式分类（chips + 直播间瀑布流） ====================
    if (widget.isDouyin) {
      return Obx(() {
        final categoriesList = widget.controller.categories;
        if (categoriesList.isEmpty || _tabController == null || _tabController!.length != categoriesList.length) {
          return BasePageView<AreasListController, LiveArea>(
            controller: widget.controller,
            enableRefresh: true,
            enableLoadMore: false,
            showPageSizeSelector: false,
            pageSizeOptions: SettingsService.to.page.pageSizeOptions,
            emptyBuilder: (context) => EmptyView(
              icon: Remix.apps_2_line,
              title: i18n("empty_areas_title"),
              subtitle: i18n("empty_areas_subtitle"),
              buttonText: i18n('refresh'),
              onButtonPressed: () => widget.controller.refreshData(),
            ),
            contentBuilder: (context, displayList, scrollController) {
              return const SizedBox.shrink();
            },
          );
        }

        return Column(
          children: [
            TabBar(
              controller: _tabController!,
              isScrollable: true,
              tabs: categoriesList.map((e) => Tab(text: e.name)).toList(),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController!,
                children: categoriesList.asMap().entries.map((entry) {
                  return _DouyinCategoryPage(
                    controller: widget.controller,
                  );
                }).toList(),
              ),
            ),
          ],
        );
      });
    }

    // ==================== 其他平台：原逻辑（顶级tab + 子分区卡片） ====================
    return Obx(() {
      final categoriesList = widget.controller.categories;

      if (categoriesList.isEmpty || _tabController == null || _tabController!.length != categoriesList.length) {
        return BasePageView<AreasListController, LiveArea>(
          controller: widget.controller,
          enableRefresh: true,
          enableLoadMore: false,
          showPageSizeSelector: false,
          pageSizeOptions: SettingsService.to.page.pageSizeOptions,
          emptyBuilder: (context) => EmptyView(
            icon: Remix.apps_2_line,
            title: i18n("empty_areas_title"),
            subtitle: i18n("empty_areas_subtitle"),
            buttonText: i18n('refresh'),
            onButtonPressed: () => widget.controller.refreshData(),
          ),
          contentBuilder: (context, displayList, scrollController) {
            return const SizedBox.shrink();
          },
        );
      }

      return Column(
        children: [
          TabBar(
            controller: _tabController!,
            isScrollable: true,
            tabs: categoriesList.map((e) => Tab(text: e.name)).toList(),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController!,
              children: categoriesList.asMap().entries.map((entry) {
                final index = entry.key;
                final category = entry.value;

                return BasePageView<AreasListController, LiveArea>(
                  key: ValueKey("area_page_${category.name}"),
                  controller: widget.controller,
                  enableRefresh: true,
                  enableLoadMore: true,
                  customMobileBottomPadding: 85,
                  customDesktopBottomPadding: 135,
                  showScrollToTopBtn: SettingsService.to.page.showScrollToTopBtn.v,
                  showPageSizeSelector: SettingsService.to.page.showPageSizeSelector.v,
                  pageSizeOptions: SettingsService.to.page.pageSizeOptions,
                  emptyBuilder: (context) => EmptyView(
                    icon: Remix.apps_2_line,
                    title: i18n("empty_areas_title"),
                    subtitle: i18n("empty_areas_subtitle"),
                  ),
                  contentBuilder: (context, displayList, scrollController) {
                    final bool isCurrentTab = widget.controller.tabIndex.value == index;
                    final List<LiveArea> finalData = isCurrentTab ? displayList : category.children;

                    if (finalData.isEmpty) {
                      return EmptyView(
                        icon: Remix.apps_2_line,
                        title: i18n("empty_areas_title"),
                        subtitle: i18n("empty_areas_subtitle"),
                      );
                    }

                    return buildFlattenAreasView(finalData, scrollController);
                  },
                );
              }).toList(),
            ),
          ),
        ],
      );
    });
  }

  Widget buildFlattenAreasView(List<LiveArea> childrenList, ScrollController scrollController) {
    return LayoutBuilder(
      builder: (context, constraint) {
        final width = constraint.maxWidth;
        final crossAxisCount = width > 1280 ? 9 : (width > 960 ? 7 : (width > 640 ? 5 : 3));

        return WaterfallFlow.builder(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 80),
          controller: scrollController,
          gridDelegate: SliverWaterfallFlowDelegateWithFixedCrossAxisCount(
            lastChildLayoutTypeBuilder: (index) => LastChildLayoutType.none,
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: SettingsService.to.theme.crossAxisSpacing.v,
            mainAxisSpacing: SettingsService.to.theme.mainAxisSpacing.v,
          ),
          itemCount: childrenList.length,
          itemBuilder: (context, index) => AreaCard(category: childrenList[index]),
        );
      },
    );
  }
}

/// 抖音单个顶级分类页：chips + 直播间瀑布流
class _DouyinCategoryPage extends StatelessWidget {
  final AreasListController controller;
  const _DouyinCategoryPage({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      return Column(
        children: [
          // 一级分区 chips（含"全部"）—— 仅当顶级分类有可切换的子分区（多于自身）
          if (controller.subAreas.length > 1)
            _buildChips(context, controller.subAreas, controller.selectedArea, (a) => controller.selectSub(a), firstIsAll: true),
          // 二级分区 chips（如游戏→竞技→王者）—— 仅当一级分区还有下级
          // 注意：二级 children 第一位就是真实游戏（如王者荣耀），不带"全部"
          if (controller.tertAreas.isNotEmpty)
            _buildChips(context, controller.tertAreas, controller.selectedArea, (a) => controller.selectTert(a)),
          const SizedBox(height: 4),
          Expanded(child: _buildRooms(context)),
        ],
      );
    });
  }

  Widget _buildChips(BuildContext context, List<LiveArea> areas, LiveArea? selected, ValueChanged<LiveArea> onTap,
      {bool firstIsAll = false}) {
    if (areas.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: areas.asMap().entries.map((e) {
            final idx = e.key;
            final area = e.value;
            // 仅一级 chips 首位展示"全部"（=顶级分区自身）；二级 chips 首位就是真实游戏
            final isAll = firstIsAll && idx == 0;
            final isSelected = area.areaId == (selected?.areaId ?? '');
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(isAll ? "全部" : (area.areaName ?? '')),
                selected: isSelected,
                onSelected: (_) => onTap(area),
                visualDensity: VisualDensity.compact,
                labelStyle: TextStyle(fontSize: 12, color: isSelected ? Colors.white : null),
                selectedColor: Theme.of(context).colorScheme.primary,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildRooms(BuildContext context) {
    final rooms = controller.rooms;
    if (rooms.isEmpty) {
      if (controller.roomsLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Remix.live_line, size: 40, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              controller.roomsError ? "直播间获取失败，下拉重试" : "暂无直播",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => controller.refreshRooms(),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 300) {
            controller.loadMoreRooms();
          }
          return false;
        },
        child: LayoutBuilder(
          builder: (context, constraint) {
            final width = constraint.maxWidth;
            final crossAxisCount = width > 1280 ? 8 : (width > 960 ? 6 : (width > 640 ? 4 : 2));
            return WaterfallFlow.builder(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 80),
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              gridDelegate: SliverWaterfallFlowDelegateWithFixedCrossAxisCount(
                lastChildLayoutTypeBuilder: (index) => LastChildLayoutType.none,
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: SettingsService.to.theme.crossAxisSpacing.v,
                mainAxisSpacing: SettingsService.to.theme.mainAxisSpacing.v,
              ),
              itemCount: rooms.length,
              itemBuilder: (context, index) => RoomCard(room: rooms[index], dense: true),
            );
          },
        ),
      ),
    );
  }
}