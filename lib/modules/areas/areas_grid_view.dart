import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:waterfall_flow/waterfall_flow.dart';
import 'package:pure_live/modules/areas/widgets/area_card.dart';
import 'package:pure_live/modules/areas/areas_list_controller.dart';
import 'package:pure_live/common/widgets/room_card.dart';

class AreaGridView extends StatefulWidget {
  final String tag;
  const AreaGridView(this.tag, {super.key});
  AreasListController get controller => Get.find<AreasListController>(tag: tag);

  bool get isFlatten => tag == Sites.douyinSite && tag == 'never_flatten';
  bool get isDouyin => tag == Sites.douyinSite;

  @override
  State<AreaGridView> createState() => _AreaGridViewState();
}

class _AreaGridViewState extends State<AreaGridView> with TickerProviderStateMixin {
  TabController? _tabController;
  Worker? _listWorker;
  final ScrollController _roomScroll = ScrollController();

  AreasListController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    if (!widget.isFlatten) {
      _listWorker = ever(widget.controller.categories, (_) => _createTabController());
      _createTabController();
      widget.controller.tabIndex.addListener(_handleExternalIndexChange);
    }
    if (widget.isDouyin) {
      _roomScroll.addListener(_handleRoomScroll);
    }
  }

  void _handleRoomScroll() {
    if (!_roomScroll.hasClients) return;
    if (_roomScroll.position.extentAfter < 300) {
      controller.loadMoreRooms();
    }
  }

  void _createTabController() {
    if (widget.isFlatten) return;
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
    if (!widget.isFlatten) {
      widget.controller.tabIndex.removeListener(_handleExternalIndexChange);
      _listWorker?.dispose();
      if (_tabController != null) {
        _tabController!.removeListener(_handleInternalTabChange);
        _tabController!.dispose();
      }
    }
    _roomScroll.removeListener(_handleRoomScroll);
    _roomScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isFlatten) {
      return BasePageView<AreasListController, LiveArea>(
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
          return buildFlattenAreasView(displayList, scrollController);
        },
      );
    }

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
                    scrollController: _roomScroll,
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
  final ScrollController scrollController;
  const _DouyinCategoryPage({required this.controller, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      return Column(
        children: [
          // 一级分区 chips（含"全部"）—— 仅当顶级分类有子分区
          if (controller.subAreas.isNotEmpty)
            _buildChips(controller.subAreas, controller.selectedArea, (a) => controller.selectSub(a)),
          // 二级分区 chips（如游戏→竞技→王者）—— 仅当一级分区还有下级
          if (controller.tertAreas.isNotEmpty)
            _buildChips(controller.tertAreas, controller.selectedArea, (a) => controller.selectTert(a)),
          const SizedBox(height: 4),
          Expanded(child: _buildRooms(context)),
        ],
      );
    });
  }

  Widget _buildChips(List<LiveArea> areas, LiveArea? selected, ValueChanged<LiveArea> onTap) {
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
            final isAll = idx == 0;
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
              controller: scrollController,
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              gridDelegate: SliverWaterfallFlowDelegateWithFixedCrossAxisCount(
                lastChildLayoutTypeBuilder: (index) => LastChildLayoutType.none,
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: SettingsService.to.theme.crossAxisSpacing.v,
                mainAxisSpacing: SettingsService.to.theme.mainAxisSpacing.v,
              ),
              itemCount: rooms.length,
              itemBuilder: (context, index) => RoomCard(room: rooms[index]),
            );
          },
        ),
      ),
    );
  }
}