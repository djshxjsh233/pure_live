import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'dart:developer' as developer;
import 'package:cookie_jar/cookie_jar.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/model/live_anchor_item.dart';
import 'package:pure_live/plugins/fake_useragent.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/danmaku/empty_danmaku.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';

class KuaishowSite implements LiveSite {
  // 列表接口结果缓存: 快手列表接口一次返回大量在播房间, 全量拉一次并缓存可避免关注页批量刷新时逐房间打 home/list + gameboard
  static Map<String, Map<String, dynamic>> _listRoomCache = {};
  static DateTime? _listCacheTime;
  // 快手流地址带时效签名(约10分钟内过期), 播放必须是新鲜链接, 不做长缓存
  static const Duration _listCacheTtl = Duration(seconds: 20);

  @override
  String id = "kuaishou";

  @override
  String name = "快手直播";

  String cookie = '';
  Map<String, String> cookieObj = {};
  List<String> imageExtensions = [
    'svgz',
    'pjp',
    'png',
    'ico',
    'avif',
    'tiff',
    'tif',
    'jfif',
    'svg',
    'xbm',
    'pjpeg',
    'webp',
    'jpg',
    'jpeg',
    'bmp',
    'gif',
  ];
  @override
  LiveDanmaku getDanmaku() => EmptyDanmaku();

  @override
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    List<LiveCategory> categories = [
      LiveCategory(id: "1", name: "热门", children: []),
      LiveCategory(id: "2", name: "网游", children: []),
      LiveCategory(id: "3", name: "单机", children: []),
      LiveCategory(id: "4", name: "手游", children: []),
      LiveCategory(id: "5", name: "棋牌", children: []),
      LiveCategory(id: "6", name: "娱乐", children: []),
      LiveCategory(id: "7", name: "综合", children: []),
      LiveCategory(id: "8", name: "文化", children: []),
    ];

    for (var item in categories) {
      var items = await getAllSubCategores(item, 1, 30, []);
      item.children.addAll(items);
    }
    return categories;
  }

  final Map<String, dynamic> headers = {
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/107.0.0.0 Safari/537.36',
    'accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3',
    'connection': 'keep-alive',
    'sec-ch-ua': 'Google Chrome;v=107, Chromium;v=107, Not=A?Brand;v=24',
    'sec-ch-ua-platform': 'macOS',
    'Sec-Fetch-Dest': 'document',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'same-origin',
    'Sec-Fetch-User': '?1',
  };

  Future<List<LiveArea>> getAllSubCategores(
    LiveCategory liveCategory,
    int page,
    int pageSize,
    List<LiveArea> allSubCategores,
  ) async {
    try {
      var subsArea = await getSubCategores(liveCategory, page, pageSize);
      allSubCategores.addAll(subsArea);
      var hasMore = subsArea.length >= pageSize;
      if (hasMore) {
        page++;
        await getAllSubCategores(liveCategory, page, pageSize, allSubCategores);
      }
      return allSubCategores;
    } catch (e) {
      return allSubCategores;
    }
  }

  Future<List<LiveArea>> getSubCategores(LiveCategory liveCategory, int page, int pageSize) async {
    var result = await HttpClient.instance.getJson(
      "https://live.kuaishou.com/live_api/category/data",
      queryParameters: {"type": liveCategory.id, "page": page, "size": pageSize},
      header: headers,
    );

    List<LiveArea> subs = [];
    for (var item in result["data"]["list"] ?? []) {
      var subCategory = LiveArea(
        areaId: item["id"],
        areaName: item["name"],
        areaType: liveCategory.id,
        platform: Sites.kuaishouSite,
        areaPic: item["poster"],
        typeName: liveCategory.name,
      );
      subs.add(subCategory);
    }

    return subs;
  }

  bool isImage(String url) {
    if (url.isEmpty) {
      return false;
    }
    var ext = url.split('.').last;
    return imageExtensions.contains(ext.toLowerCase());
  }

  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    var api = category.areaId!.length < 7
        ? "https://live.kuaishou.com/live_api/gameboard/list"
        : "https://live.kuaishou.com/live_api/non-gameboard/list";
    var result = await HttpClient.instance.getJson(
      api,
      queryParameters: {"filterType": 0, "pageSize": 20, "gameId": category.areaId, "page": page},
      header: headers,
    );
    var items = <LiveRoom>[];
    for (var item in result["data"]["list"]) {
      var roomItem = LiveRoom(
        roomId: item["author"]["id"] ?? '',
        title: item['caption'] ?? '',
        cover: isImage(item['poster']) ? item['poster'].toString() : '${item['poster'].toString()}.jpg',
        nick: item["author"]["name"].toString(),
        watching: item["watchingCount"].toString(),
        avatar: item["author"]["avatar"],
        area: item["gameInfo"]["name"].toString(),
        liveStatus: LiveStatus.live,
        status: true,
        platform: Sites.kuaishouSite,
        data: item["playUrls"],
      );
      items.add(roomItem);
    }
    return items;
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) {
    List<LivePlayQuality> qualities = <LivePlayQuality>[];
    developer.log(detail.data.toString(), name: 'detail.data');
    // 兼容两种 playUrls 结构:
    // 列表接口: [{adaptationSet:{representation:[...]}}]
    // 详情接口: {h264:{adaptationSet:{representation:[...]}}, hevc:{...}}
    var data = detail.data;
    if (data == null) return Future.value(qualities);
    List qulityList = [];
    if (data is List) {
      if (data.isNotEmpty && data[0] is Map) {
        var adaptationSet = data[0]["adaptationSet"];
        if (adaptationSet is Map && adaptationSet["representation"] is List) {
          qulityList = adaptationSet["representation"] as List;
        }
      }
    } else if (data is Map) {
      var h264 = data["h264"];
      if (h264 is Map) {
        var adaptationSet = h264["adaptationSet"];
        if (adaptationSet is Map && adaptationSet["representation"] is List) {
          qulityList = adaptationSet["representation"] as List;
        }
      }
    } else if (data is List && data.isNotEmpty && data[0] is Map && data[0]["url"] != null) {
      // 快手移动版新结构: [{url, bitrate, codec, cdn, ...}] 直接就是流地址
      qulityList = data as List;
    }

    for (var quality in qulityList) {
      var qName = quality["name"];
      var qSort = quality["level"];
      if (qName == null && qSort == null && quality["url"] != null) {
        // 快手移动版新结构: 只有 url/bitrate/cdn, 用 bitrate 生成清晰度名
        qName = '${quality["bitrate"] ?? 0}kbps';
        qSort = quality["bitrate"] ?? 0;
      }
      if (quality["url"] == null) continue;
      var qualityItem = LivePlayQuality(
        quality: qName?.toString() ?? '默认',
        sort: qSort is num ? qSort.toInt() : 0,
        data: <String>[quality["url"].toString()],
      );
      qualities.add(qualityItem);
    }
    qualities.sort((a, b) => b.sort.compareTo(a.sort));
    return Future.value(qualities);
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    return quality.data as List<String>;
  }

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    try {
      var resultText = await HttpClient.instance.getJson(
        "https://live.kuaishou.com/live_api/home/list",
        header: headers,
      );

      var result = resultText['data']['list'] ?? [];
      var items = <LiveRoom>[];
      for (var item in result) {
        for (var sitem in item["gameLiveInfo"]) {
          for (var titem in sitem["liveInfo"]) {
            var author = titem["author"];
            var gameInfo = titem["gameInfo"];
            var roomItems = LiveRoom(
              cover: gameInfo['poster'].toString(),
              watching: titem["watchingCount"].toString(),
              roomId: author["id"],
              userId: author["id"].toString(),
              area: gameInfo["name"],
              title: author['description'] != null ? author['description'].replaceAll('\n', ' ') : '',
              nick: author["name"].toString(),
              avatar: author["avatar"].toString(),
              introduction: author["description"] != null ? author["description"].replaceAll("\n", " ") : '',
              notice: author["description"],
              status: true,
              liveStatus: LiveStatus.live,
              platform: Sites.kuaishouSite,
              data: titem["playUrls"],
            );
            items.add(roomItems);
          }
        }
      }
      return items;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future registerDid() async {
    var res = await HttpClient.instance.postJson(
      'https://log-sdk.ksapisrv.com/rest/wd/common/log/collect/misc2?v=3.9.49&kpn=KS_GAME_LIVE_PC',
      header: headers,
      data: misc2dic(cookieObj['did']!),
    );
    return res;
  }

  Map<String, Object> misc2dic(String did) {
    var map = {
      'common': {
        'identity_package': {'device_id': did, 'global_id': ''},
        'app_package': {'language': 'zh-CN', 'platform': 10, 'container': 'WEB', 'product_name': 'KS_GAME_LIVE_PC'},
        'device_package': {
          'os_version': 'NT 6.1',
          'model': 'Windows',
          'ua':
              'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/86.0.4240.198 Safari/537.36',
        },
        'need_encrypt': 'false',
        'network_package': {'type': 3},
        'h5_extra_attr':
            '{"sdk_name":"webLogger","sdk_version":"3.9.49","sdk_bundle":"log.common.js","app_version_name":"","host_product":"","resolution":"1600x900","screen_with":1600,"screen_height":900,"device_pixel_ratio":1,"domain":"https://live.kuaishou.com"}',
        'global_attr': '{}',
      },
      'logs': [
        {
          'client_timestamp': DateTime.now().millisecondsSinceEpoch,
          'client_increment_id': math.Random().nextInt(8999) + 1000,
          'session_id': '1eb20f88-51ac-4ecf-8dc3-ace5aefcae4f',
          'time_zone': 'GMT+08:00',
          'event_package': {
            'task_event': {
              'type': 1,
              'status': 0,
              'operation_type': 1,
              'operation_direction': 0,
              'session_id': '1eb20f88-51ac-4ecf-8dc3-ace5aefcae4f',
              'url_package': {
                'page': 'GAME_DETAL_PAGE',
                'identity': '5316c78e-f0b6-4be2-a076-c8f9d11ebc0a',
                'page_type': 2,
                'params': '{"game_id":1001,"game_name":"王者荣耀"}',
              },
              'element_package': {},
            },
          },
        },
      ],
    };
    return map;
  }

  // 获取pageId
  String getPageId() {
    var pageId = '';
    const charset = 'bjectSymhasOwnProp-0123456789ABCDEFGHIJKLMNQRTUVWXYZ_dfgiklquvxz';
    for (var i = 0; i < 16; i++) {
      pageId += charset[math.Random().nextInt(63)];
    }
    var currentTime = DateTime.now().millisecondsSinceEpoch;
    return pageId += '_$currentTime';
  }

  Future getCookie(String url) async {
    final dio = Dio();
    final cookieJar = CookieJar();
    dio.interceptors.add(CookieManager(cookieJar));
    await dio.get(url);
    List<Cookie> cookies = await cookieJar.loadForRequest(Uri.parse(url));
    cookie = '';
    for (var i = 0; i < cookies.length; i++) {
      if (i != cookies.length - 1) {
        cookie += "${cookies[i].name}=${cookies[i].value};";
      } else {
        cookie += "${cookies[i].name}=${cookies[i].value}";
      }
      cookieObj[cookies[i].name] = cookies[i].value;
    }
  }

  Future getWebsocketUrl(String liveRoomId) async {
    var variables = {'liveStreamId': liveRoomId};
    var query =
        r'query WebSocketInfoQuery($liveStreamId: String) {\n  webSocketInfo(liveStreamId: $liveStreamId) {\n    token\n    webSocketUrls\n    __typename\n  }\n}\n';
    var res = await HttpClient.instance.postJson(
      'https://live.kuaishou.com/live_graphql',
      header: headers,
      data: {"operationName": 'WebSocketInfoQuery', "variables": variables, "query": query},
    );
    return res;
  }

  @override
  Future<LiveRoom> getRoomDetail({required String platform, required String roomId}) async {
    // 快手列表接口(home/list + gameboard/list)匿名直达所有在播房间的有效 playUrls,
    // 与浏览器秒播机制一致。优先匹配列表拿到 playUrls, 避免逐房间慢速页面抓取。
    try {
      final listRoom = await _fetchLiveRoomFromLists(roomId, platform);
      if (listRoom != null && (listRoom.data as List?)?.isNotEmpty == true) {
        return listRoom;
      }
    } catch (e) {
      developer.log('快手列表匹配失败: $e');
    }

    try {
      // 列表匹配不到时, 走移动版页面(livev.m.chenzhongtech.com)实时取流
      final mobileRoom = await _fetchMobileRoomDetail(roomId, platform);
      if (mobileRoom != null) return mobileRoom;
    } catch (e) {
      developer.log('快手移动版详情失败: $e');
    }

    headers['cookie'] = cookie;
    var url = "https://live.kuaishou.com/u/$roomId";
    var mHeaders = headers;
    var fakeUseragent = FakeUserAgent.getRandomUserAgent();
    mHeaders['User-Agent'] = fakeUseragent['userAgent'];
    mHeaders['sec-ch-ua'] = 'Google Chrome;v=${fakeUseragent['v']}, Chromium;v=${fakeUseragent['v']}, Not=A?Brand;v=24';
    mHeaders['sec-ch-ua-platform'] = fakeUseragent['device'];
    mHeaders['sec-fetch-dest'] = 'document';
    mHeaders['sec-fetch-mode'] = 'navigate';
    mHeaders['sec-fetch-site'] = 'same-origin';
    mHeaders['sec-fetch-user'] = '?1';
    if (SettingsService.to.cookieManager.kuaishouCookie.v.isNotEmpty) {
      mHeaders['cookie'] = SettingsService.to.cookieManager.kuaishouCookie.v;
    }

    mHeaders['accept'] =
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9';
    await getCookie(url);
    await registerDid();
    var resultText = await HttpClient.instance.getText(url, queryParameters: {}, header: mHeaders);

    try {
      var text = RegExp(r"window\.__INITIAL_STATE__=(.*?);", multiLine: false).firstMatch(resultText)?.group(1);

      var transferData = text!.replaceAll("undefined", "null");

      var jsonObj = jsonDecode(transferData);
      var liveStream = jsonObj["liveroom"]["playList"][0]["liveStream"];
      var author = jsonObj["liveroom"]["playList"][0]["author"];
      var gameInfo = jsonObj["liveroom"]["playList"][0]["gameInfo"];
      var liveStreamId = liveStream["id"];
      return LiveRoom(
        cover: isImage(liveStream['poster'])
            ? liveStream['poster'].toString()
            : '${liveStream['poster'].toString()}.jpg',
        watching: jsonObj["liveroom"]["playList"][0]["isLiving"] ? gameInfo["watchingCount"].toString() : '0',
        roomId: author["id"],
               userId: author["id"].toString(),
        area: gameInfo["name"] ?? '',
        title: author["description"] != null ? author["description"].replaceAll("\n", " ") : '',
        nick: author["name"].toString(),
        avatar: author["avatar"].toString(),
        introduction: author["description"].toString(),
        notice: author["description"].toString(),
        status: jsonObj["liveroom"]["playList"][0]["isLiving"],
        liveStatus: jsonObj["liveroom"]["playList"][0]["isLiving"] ? LiveStatus.live : LiveStatus.offline,
        platform: Sites.kuaishouSite,
        link: liveStreamId,
        data: liveStream["playUrls"],
      );
    } catch (e) {
      // SSR 拿不到时回退到列表接口(home/list + gameboard/list), 按 roomId 匹配在播房间与 playUrls
      final fallback = await _fetchLiveRoomFromLists(roomId, platform);
      if (fallback != null) return fallback;

      LiveRoom liveRoom =
          SettingsService.to.fav.favoriteRooms.v.firstWhereOrNull(
            (r) => r.roomId == roomId && r.platform == platform,
          ) ??
          LiveRoom(roomId: roomId, platform: platform);

      // 请求失败时保留原状态(如强制标记为未开播), 避免主播明明已开播却因接口失败被误判下播
      return liveRoom;
    }
  }

  /// 移动版页面(livev.m.chenzhongtech.com/fw/live/{id}) 会直接返回真实 playUrls(新结构)。
  /// 桌面站 SSR 已不输出直播流, 必须用移动域名+移动UA 才能拿到。
  Future<LiveRoom?> _fetchMobileRoomDetail(String roomId, String platform) async {
    try {
      final mUrl = 'https://livev.m.chenzhongtech.com/fw/live/$roomId';
      final mobileHeaders = <String, dynamic>{
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 16; 25102RKBEC Build/BP2A.250605.031.A3) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/143.0.7499.192 Mobile Safari/537.36',
        'accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3',
        'sec-ch-ua': '"Android WebView";v="143", "Chromium";v="143", "Not A(Brand";v="24"',
        'sec-ch-ua-mobile': '?1',
        'sec-ch-ua-platform': '"Android"',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'same-origin',
        'Referer': 'https://livev.m.chenzhongtech.com/',
      };
      if (SettingsService.to.cookieManager.kuaishouCookie.v.isNotEmpty) {
        mobileHeaders['cookie'] = SettingsService.to.cookieManager.kuaishouCookie.v;
      }
      final mText = await HttpClient.instance.getText(mUrl, queryParameters: {}, header: mobileHeaders);
      if (!mText.contains('"playUrls"') || !mText.contains('"liveStream"')) {
        return null;
      }
      return _parseMobileRoom(mText, platform);
    } catch (e) {
      developer.log('快手移动版解析失败: $e');
      return null;
    }
  }

  LiveRoom? _parseMobileRoom(String html, String platform) {
    try {
      final initState = _extractInitState(html);
      if (initState == null) return null;
      final roomObj = _findLiveRoom(initState);
      if (roomObj == null) return null;
      final liveStream = roomObj['liveStream'] ?? {};
      final user = liveStream['user'] ?? {};
      final isLiving = liveStream['living'] == true || (liveStream['playUrls'] ?? []).isNotEmpty;
      // 画质列表: multiResolutionPlayUrls 是 [{name, level, urls:[{url,...}]}]
      // 直接映射为 [{name, level, url}] 供 getPlayQualites 使用
      final qualities = <Map<String, dynamic>>[];
      final multi = liveStream['multiResolutionPlayUrls'];
      if (multi is List) {
        for (final m in multi) {
          if (m is! Map) continue;
          final urls = m['urls'];
          if (urls is List && urls.isNotEmpty && urls[0] is Map && urls[0]['url'] != null) {
            qualities.add({
              'name': m['name'] ?? '',
              'level': m['level'] ?? 0,
              'url': urls[0]['url'],
            });
          }
        }
      }
      // 兜底: 没有多档画质时用单档 playUrls
      if (qualities.isEmpty) {
        final playUrls = liveStream['playUrls'];
        if (playUrls is List) {
          for (final u in playUrls) {
            if (u is Map && u['url'] != null) {
              qualities.add({
                'name': '默认',
                'level': 0,
                'url': u['url'],
              });
            }
          }
        }
      }
      return LiveRoom(
        cover: (user['headurl'] ?? liveStream['coverUrl'] ?? '').toString(),
        watching: (roomObj['currentWatching'] ?? 0).toString(),
        roomId: user['kwaiId']?.toString() ?? '',
        userId: (user['user_id'] ?? liveStream['liveStreamId'] ?? '').toString(),
        area: (roomObj['host-name'] ?? '').toString(),
        title: (liveStream['caption'] ?? '').toString(),
        nick: (user['user_name'] ?? '').toString(),
        avatar: (user['headurl'] ?? '').toString(),
        introduction: (liveStream['caption'] ?? '').toString(),
        notice: (liveStream['caption'] ?? '').toString(),
        status: isLiving,
        liveStatus: isLiving ? LiveStatus.live : LiveStatus.offline,
        platform: platform,
        link: (liveStream['liveStreamId'] ?? '').toString(),
        data: qualities,
      );
    } catch (e) {
      developer.log('快手移动版解析失败2: $e');
      return null;
    }
  }

  /// 提取 window.INIT_STATE 后面的 JSON 对象
  Map<String, dynamic>? _extractInitState(String html) {
    final idx = html.indexOf('window.INIT_STATE');
    if (idx < 0) return null;
    final eq = html.indexOf('=', idx);
    if (eq < 0) return null;
    var start = eq + 1;
    while (start < html.length && (html[start] == ' ' || html[start] == '\n' || html[start] == '\r' || html[start] == '\t')) start++;
    if (start >= html.length || html[start] != '{') return null;
    var depth = 0;
    var inStr = false;
    var i = start;
    while (i < html.length) {
      final c = html[i];
      if (inStr) {
        if (c == '\\') {
          i += 2;
          continue;
        }
        if (c == '"') inStr = false;
      } else {
        if (c == '"') {
          inStr = true;
        } else if (c == '{') {
          depth++;
        } else if (c == '}') {
          depth--;
          if (depth == 0) {
            final raw = html.substring(start, i + 1);
            return jsonDecode(raw.replaceAll('undefined', 'null'));
          }
        }
      }
      i++;
    }
    return null;
  }

  /// 递归查找包含 liveStream.playUrls 的房间对象
  dynamic _findLiveRoom(dynamic node) {
    if (node is Map) {
      final ls = node['liveStream'];
      if (ls is Map && ls['playUrls'] != null) return node;
      for (final v in node.values) {
        final r = _findLiveRoom(v);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _findLiveRoom(v);
        if (r != null) return r;
      }
    }
    return null;
  }

  /// 后台列表接口可稳定返回在播房间的有效 playUrls,
  /// 在 SSR 页面被反爬/占位时按 roomId 匹配, 取回流地址用于播放。
  Future<LiveRoom?> _fetchLiveRoomFromLists(String roomId, String platform) async {
    try {
      await _ensureListCache();
      final hit = _listRoomCache[roomId];
      if (hit != null) return _roomFromListItem(hit, hit['author'], platform);
      // 缓存里没有: 刷新一次(可能新开播)
      _listRoomCache = {};
      _listCacheTime = null;
      await _ensureListCache();
      final hit2 = _listRoomCache[roomId];
      if (hit2 != null) return _roomFromListItem(hit2, hit2['author'], platform);
    } catch (e) {
      developer.log('快手列表回退失败: $e');
    }
    return null;
  }

  Future<void> _ensureListCache() async {
    if (_listCacheTime != null) {
      if (DateTime.now().difference(_listCacheTime!) < _listCacheTtl) return;
    }
    _listCacheTime = DateTime.now();
    final newCache = <String, Map<String, dynamic>>{};
    try {
      // 1. 首页推荐(home/list)
      final homeText = await HttpClient.instance.getJson(
        "https://live.kuaishou.com/live_api/home/list",
        header: headers,
      );
      final homeList = homeText['data']['list'] ?? [];
      for (final section in homeList) {
        for (final game in section['gameLiveInfo'] ?? <dynamic>[]) {
          for (final item in game['liveInfo'] ?? <dynamic>[]) {
            final author = item['author'] ?? {};
            final id = author['id']?.toString() ?? '';
            if (id.isEmpty) continue;
            final entry = Map<String, dynamic>.from(item);
            entry['author'] = author;
            newCache[id] = entry;
          }
        }
      }
      // 2) 游戏分区分页列表(gameboard/list) 并行拉取, 覆盖更广的在播房间
      final futures = <Future>[];
      for (int categoryId = 1; categoryId <= 8; categoryId++) {
        futures.add(HttpClient.instance.getJson(
          "https://live.kuaishou.com/live_api/gameboard/list",
          queryParameters: {"filterType": 0, "pageSize": 20, "gameId": '$categoryId', "page": 1},
          header: headers,
        ).then((gbText) {
          final list = gbText['data']?['list'] ?? [];
          for (final item in list) {
            final author = item['author'] ?? {};
            final id = author['id']?.toString() ?? '';
            if (id.isEmpty) continue;
            final entry = Map<String, dynamic>.from(item);
            entry['author'] = author;
            newCache[id] = entry;
          }
        }).catchError((_) {}));
      }
      await Future.wait(futures);
      _listRoomCache = newCache;
    } catch (e) {
      _listCacheTime = null;
      developer.log('快手列表拉取失败: $e');
    }
  }

  LiveRoom _roomFromListItem(dynamic item, dynamic author, String platform) {
    final gameInfo = item['gameInfo'] ?? {};
    return LiveRoom(
      cover: isImage(item['poster']) ? item['poster'].toString() : '${item['poster'].toString()}.jpg',
      watching: (item['watchingCount'] ?? 0).toString(),
      roomId: author['id']?.toString() ?? '',
      userId: author['id']?.toString() ?? '',
      area: (gameInfo['name'] ?? '').toString(),
      title: (author['description'] ?? '').toString().replaceAll('\n', ' '),
      nick: (author['name'] ?? '').toString(),
      avatar: (author['avatar'] ?? '').toString(),
      introduction: (author['description'] ?? '').toString(),
      notice: (author['description'] ?? '').toString(),
      status: true,
      liveStatus: LiveStatus.live,
      platform: platform,
      data: item['playUrls'],
    );
  }

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    // 快手无法搜索主播，只能搜索游戏分类这里不做展示
    return [];
  }

  @override
  Future<List<LiveAnchorItem>> searchAnchors(String keyword, {int page = 1, int pageSize = 30}) async {
    return [];
  }

  @override
  Future<bool> getLiveStatus({required String platform, required String roomId}) async {
    return false;
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({required String roomId}) {
    //尚不支持
    return Future.value([]);
  }
}