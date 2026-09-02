import 'dart:async';
import 'dart:convert';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/plugins/area_pic_mapper.dart';
import 'package:pure_live/core/common/core_log.dart';

class AreasListController extends ServerAllPageController<LiveArea> {
  final Site site;
  final tabIndex = 0.obs;

  final categories = <AppLiveCategory>[].obs;
  final Map<String, List<LiveArea>> _serverRawBackup = {};

  List<LiveArea> _flattenRawAllData = [];

  bool get isFlatten => site.id == Sites.douyinSite && site.id == 'never_flatten';

  // ==================== 抖音浏览器式分类（直播间 + 多级chips） ====================
  /// 当前顶级分类下的一级分区 chips（含"全部"= 顶级自身）
  final subAreas = <LiveArea>[].obs;
  /// 当前一级分区下的二级分区 chips（仅当一级分区还有下级，如游戏→竞技→王者）
  final tertAreas = <LiveArea>[].obs;
  /// 当前生效分区（默认=顶级自身"全部"）
  LiveArea? selectedArea;
  /// 当前顶级分类
  AppLiveCategory? currentCategory;
  /// 直播间列表（抖音）
  final rooms = <LiveRoom>[].obs;
  int _roomPage = 1;
  bool roomsLoading = false;
  bool roomsMore = true;
  bool roomsError = false;
  String roomsErrorMsg = "";
  int _loadSeq = 0;

  bool get isDouyin => site.id == Sites.douyinSite;

  AreasListController(this.site);

  @override
  Future<List<LiveArea>> fetchAllServerData() async {
    var result = await site.liveSite.getCategores(1, 1000);
    var channels = result.map((e) => AppLiveCategory.fromLiveCategory(e)).toList();
    AreaPicMapper.updateAreaListMaps(channels);

    _serverRawBackup.clear();

    if (isFlatten) {
      _flattenRawAllData = channels.expand((e) => e.children).toList();
      categories.assignAll(channels);
      return _flattenRawAllData;
    } else {
      for (var cat in channels) {
        _serverRawBackup[cat.id] = List.from(cat.children);
      }
      categories.assignAll(channels);
      // 抖音：初始化顶级分类与默认选中（"全部"=顶级自身），并加载首个顶级分类的直播间
      if (isDouyin) {
        _resetDouyinTop(tabIndex.value, notifyRooms: true);
      }
      return _getCurrentTabAllChildren();
    }
  }

  // ==================== 抖音分类逻辑 ====================

  /// 切换顶级分类 tab（抖音）
  void switchDouyinTop(int index) {
    if (tabIndex.value != index) tabIndex.value = index;
    _resetDouyinTop(index);
  }

  void _resetDouyinTop(int index, {bool notifyRooms = true}) {
    if (index < 0 || index >= categories.length) return;
    final cat = categories[index];
    currentCategory = cat;
    final children = cat.children;
    subAreas.assignAll(children);
    // 默认选中"全部"（children 首位为顶级自身，由 getCategores 注入）
    selectedArea = children.isNotEmpty ? children.first : null;
    tertAreas.assignAll([]);
    if (notifyRooms) {
      _loadRooms(refresh: true);
    }
  }

  /// 选择一级分区 chip（如"竞技游戏"）
  void selectSub(LiveArea area) {
    selectedArea = area;
    final children = area.children ?? [];
    // 一级分区下还有二级分区（游戏第二级）→ 显示二级 chips，默认选"全部"（该一级分区自身）
    if (children.isNotEmpty) {
      tertAreas.assignAll(children);
    } else {
      tertAreas.assignAll([]);
    }
    _loadRooms(refresh: true);
  }

  /// 选择二级分区 chip（如"王者荣耀"）
  void selectTert(LiveArea area) {
    selectedArea = area;
    _loadRooms(refresh: true);
  }

  /// 加载当前分区的直播间（服务端分页）
  Future<void> _loadRooms({bool refresh = false}) async {
    final area = selectedArea;
    if (area == null || roomsLoading) return;
    if (refresh) {
      _roomPage = 1;
      roomsMore = true;
      roomsError = false;
      roomsErrorMsg = "";
    }
    if (!roomsMore && !refresh) return;
    roomsLoading = true;
    final seq = ++_loadSeq;
    final page = _roomPage;
    try {
      final list = await site.liveSite.getCategoryRooms(
        area,
        page: page,
        pageSize: 30,
      );
      if (seq != _loadSeq) return; // 过期请求丢弃
      if (refresh) {
        rooms.assignAll(list);
      } else {
        rooms.addAll(list);
      }
      roomsMore = list.length >= 30;
      if (roomsMore) _roomPage++;
    } catch (e) {
      if (seq != _loadSeq) return;
      roomsError = true;
      roomsErrorMsg = e.toString();
      CoreLog.error("抖音分类直播间加载失败: $e");
    } finally {
      roomsLoading = false;
    }
  }

  /// 触底加载更多（由UI滚动监听调用）
  void loadMoreRooms() {
    if (!roomsLoading && roomsMore) {
      _loadRooms();
    }
  }

  /// 下拉刷新当前分区直播间
  void refreshRooms() {
    if (roomsLoading) return;
    _loadRooms(refresh: true);
  }

  // ==================== 原有逻辑（非抖音平台） ====================

  List<LiveArea> _getCurrentTabAllChildren() {
    if (isFlatten) {
      return _flattenRawAllData;
    }
    int activeIndex = tabIndex.value;
    if (activeIndex >= categories.length || categories.isEmpty) {
      return [];
    }
    final catId = categories[activeIndex].id;
    return _serverRawBackup[catId] ?? [];
  }

  @override
  void processLocalPaging() {
    if (isFlatten) {
      final allItems = _flattenRawAllData;
      totalCount.value = allItems.length;

      if (allItems.isEmpty) {
        list.clear();
        canLoadMore.value = false;
        pageEmpty.value = true;
        finishRefreshControllers(IndicatorResult.noMore);
        return;
      }

      if (Get.width > 680) {
        int startIndex = (currentPage - 1) * pageSize.value;
        if (startIndex >= allItems.length) {
          currentPage = 1;
          startIndex = 0;
        }

        int endIndex = startIndex + pageSize.value;
        if (endIndex > allItems.length) endIndex = allItems.length;

        final newData = allItems.sublist(startIndex, endIndex);
        list.assignAll(newData);
        canLoadMore.value = endIndex < allItems.length;
        pageEmpty.value = list.isEmpty;
        finishRefreshControllers(canLoadMore.value ? IndicatorResult.success : IndicatorResult.noMore);
        if (currentPage == 1) {
          scrollToTopImmediate();
        }
      } else {
        list.assignAll(allItems);
        canLoadMore.value = false;
        pageEmpty.value = list.isEmpty;
        finishRefreshControllers(IndicatorResult.noMore);
      }
      return;
    }

    int activeIndex = tabIndex.value;
    if (categories.isEmpty || activeIndex >= categories.length) {
      list.clear();
      canLoadMore.value = false;
      pageEmpty.value = true;
      categories.refresh();
      finishRefreshControllers(IndicatorResult.noMore);
      return;
    }

    final currentCategory = categories[activeIndex];
    final allItems = _getCurrentTabAllChildren();
    totalCount.value = allItems.length;

    if (allItems.isEmpty) {
      currentCategory.children.clear();
      list.clear();
      canLoadMore.value = false;
      pageEmpty.value = true;
      categories.refresh();
      finishRefreshControllers(IndicatorResult.noMore);
      return;
    }

    if (Get.width > 680) {
      int startIndex = (currentPage - 1) * pageSize.value;
      if (startIndex >= allItems.length) {
        currentPage = 1;
        startIndex = 0;
      }

      int endIndex = startIndex + pageSize.value;
      if (endIndex > allItems.length) endIndex = allItems.length;

      final newData = allItems.sublist(startIndex, endIndex);
      list.assignAll(newData);
      currentCategory.children.assignAll(newData);
      canLoadMore.value = endIndex < allItems.length;
      pageEmpty.value = list.isEmpty;
      if (currentPage == 1) {
        scrollToTopImmediate();
      }
      finishRefreshControllers(canLoadMore.value ? IndicatorResult.success : IndicatorResult.noMore);
    } else {
      list.assignAll(allItems);
      currentCategory.children.assignAll(allItems);
      canLoadMore.value = false;
      pageEmpty.value = list.isEmpty;
      finishRefreshControllers(IndicatorResult.noMore);
    }

    categories.refresh();
  }
}

class AppLiveCategory extends LiveCategory {
  AppLiveCategory({required super.id, required super.name, required super.children});

  factory AppLiveCategory.fromLiveCategory(LiveCategory item) {
    return AppLiveCategory(children: item.children, id: item.id, name: item.name);
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = id;
    json['name'] = name;
    json['children'] = children.map((LiveArea e) => jsonEncode(e.toJson())).toList();
    return json;
  }
}