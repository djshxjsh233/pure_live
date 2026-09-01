import 'dart:convert';
import 'dart:math' as math;
import 'package:pure_live/common/index.dart';
import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/model/live_anchor_item.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/core/scripts/douyin_sign.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/common/convert_helper.dart';
import 'package:pure_live/core/danmaku/douyin_danmaku.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/core/utils/douyin/douyin_request_params.dart';

class DouyinSite implements LiveSite {
  @override
  String id = "douyin";

  @override
  String name = "抖音直播";

  @override
  LiveDanmaku getDanmaku() => DouyinDanmaku();

  /// 使用 QQBrowser User-Agent（参考 DouyinLiveRecorder）
  static const String kDefaultUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.5845.97 Safari/537.36 Core/1.116.567.400 QQBrowser/19.7.6764.400";

  static const String kDefaultReferer = "https://live.douyin.com";

  static const String kDefaultAuthority = "live.douyin.com";

  static const String kDefaultCookie =
      "ttwid=1%7CB1qls3GdnZhUov9o2NxOMxxYS2ff6OSvEWbv0ytbES4%7C1680522049%7C280d802d6d478e3e78d0c807f7c487e7ffec0ae4e5fdd6a0fe74c3c6af149511";

  /// 用户设置的 cookie
  static String cookie = "";

  /// 动态获取的新鲜 cookie（模拟浏览器首次访问，置顶优先级高于内置兜底）
  static String _dynamicCookie = "";
  static DateTime? _dynamicCookieTime;

  /// 最近一次响应头下发的合法 msToken（服务端签发，风控分数低）
  static String _serverMsToken = "";

  /// web_rid → 真实房间 id_str 缓存（浏览器进房必带 room_id_str，贴近此行为可降低风控）
  static final Map<String, String> _webRidRoomIdCache = {};

  /// 动态 cookie 有效时长（ttwid 一般有效一年，这里保守点 30 分钟刷新一次）
  static const Duration _dynamicCookieLifetime = Duration(minutes: 30);

  Map<String, dynamic> headers = {
    "Authority": kDefaultAuthority,
    "Referer": kDefaultReferer,
    "User-Agent": kDefaultUserAgent,
  };

  /// 强制/按需刷新动态 cookie：HEAD live.douyin.com 拿 Set-Cookie（ttwid、__ac_nonce、msToken 等）
  Future<String> _refreshDynamicCookie({bool force = false}) async {
    try {
      final now = DateTime.now();
      if (!force &&
          _dynamicCookie.isNotEmpty &&
          _dynamicCookieTime != null &&
          now.difference(_dynamicCookieTime!) < _dynamicCookieLifetime) {
        return _dynamicCookie;
      }
      final headResp = await HttpClient.instance.head(
        "https://live.douyin.com/?from_nav=1",
        header: {
          "Authority": kDefaultAuthority,
          "Referer": kDefaultReferer,
          "User-Agent": kDefaultUserAgent,
          "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        },
      );
      var dyCookie = "";
      headResp.headers["set-cookie"]?.forEach((element) {
        final raw = element.trim();
        if (raw.isEmpty) return;
        final cookie = raw.split(";")[0].trim();
        if (cookie.startsWith("ttwid=") ||
            cookie.startsWith("__ac_nonce=") ||
            cookie.startsWith("msToken=")) {
          dyCookie += "$cookie;";
        }
      });
      if (dyCookie.isNotEmpty) {
        _dynamicCookie = dyCookie;
        _dynamicCookieTime = now;
        if (cookie.isEmpty && SettingsService.to.cookieManager.douyinCookie.v.isEmpty) {
          cookie = _dynamicCookie;
        }
        CoreLog.i("douyin 动态cookie已刷新(${dyCookie.length}字节)");
      } else {
        CoreLog.w("douyin 动态cookie刷新无结果，沿用旧值");
      }
      return _dynamicCookie;
    } catch (e) {
      CoreLog.error("douyin 刷新动态cookie失败: $e");
      return _dynamicCookie;
    }
  }

  Future<Map<String, dynamic>> getRequestHeaders() async {
    try {
      if (cookie.isNotEmpty) {
        // 用户/缓存的 cookie 可能缺少服务端下发的 msToken，补上能显著降低风控分
        if (_serverMsToken.isNotEmpty && !cookie.contains("msToken=")) {
          headers["cookie"] = "$cookie; msToken=$_serverMsToken;";
        } else {
          headers["cookie"] = cookie;
        }
        return headers;
      } else if (SettingsService.to.cookieManager.douyinCookie.v.isNotEmpty) {
        cookie = SettingsService.to.cookieManager.douyinCookie.v;
        headers["cookie"] = cookie;
        return headers;
      }

      // 内置 ttwid 是早期写死的旧值，风控识别度极高，优先动态获取一次（带缓存）
      await _refreshDynamicCookie();
      if (_dynamicCookie.isNotEmpty) {
        cookie = _dynamicCookie;
        if (_serverMsToken.isNotEmpty && !cookie.contains("msToken=")) {
          headers["cookie"] = "$cookie; msToken=$_serverMsToken;";
        } else {
          headers["cookie"] = cookie;
        }
        return headers;
      }

      headers["cookie"] = kDefaultCookie;
      return headers;
    } catch (e) {
      CoreLog.error(e);
      if (!(headers["cookie"]?.toString().isNotEmpty ?? false)) {
        headers["cookie"] = kDefaultCookie;
      }
      return headers;
    }
  }

  Future<Map<String, dynamic>> getUserInfoByCookie(String cookie) async {
    try {
      final url = "https://live.douyin.com/webcast/user/me/";
      final result = await HttpClient.instance.getJson(
        url,
        queryParameters: {"aid": DouyinRequestParams.aidValue},
        header: {
          "user-agent": DouyinRequestParams.kDefaultUserAgent,
          'accept': 'application/json, text/plain, */*',
          'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
          "Cookie": cookie,
        },
      );
      if (result is Map<String, dynamic>) {
        final data = result["data"];
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
      return {};
    } catch (e) {
      CoreLog.error(e);
    }
    return {};
  }

  String extractCategoryDataJson(String source) {
    final startPattern = r'{\"pathname\":\"/\",\"categoryData\":';
    int startIndex = source.indexOf(startPattern);
    if (startIndex == -1) return '';
    int openBraces = 0;
    bool foundFirstBrace = false;
    for (int i = startIndex; i < source.length; i++) {
      if (source[i] == '{') {
        openBraces++;
        foundFirstBrace = true;
      } else if (source[i] == '}') {
        openBraces--;
      }
      if (foundFirstBrace && openBraces == 0) {
        String rawData = source.substring(startIndex, i + 1);
        return rawData.replaceAll('\\"', '"').replaceAll(r'\\', r'\');
      }
    }
    return '';
  }

  @override
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    List<LiveCategory> categories = [];
    var result = await HttpClient.instance.getText(
      "https://live.douyin.com/",
      queryParameters: {"from_nav": "1"},
      header: await getRequestHeaders(),
    );

    String extracted = extractCategoryDataJson(result);
    var renderDataJson = json.decode(extracted);
    var data = renderDataJson["categoryData"];

    // 递归解析：把每个 partition 及其嵌套的 sub_partition 转成 LiveArea
    LiveArea parseArea(dynamic node) {
      var partition = node["partition"];
      var id = '${partition["id_str"]},${partition["type"]}';
      var name = asT<String?>(partition["title"]) ?? '';
      var subList = node["sub_partition"] as List? ?? [];
      return LiveArea(
        areaId: id,
        typeName: name,
        areaType: id,
        areaName: name,
        areaPic: "",
        platform: Sites.douyinSite,
        children: subList.isEmpty
            ? null
            : subList.map((sub) => parseArea(sub)).toList(),
      );
    }

    for (var item in data) {
      List<LiveArea> categories_ = [];
      var subList = item["sub_partition"] as List? ?? [];
      for (var subItem in subList) {
        categories_.add(parseArea(subItem));
      }
      var pid = '${item["partition"]["id_str"]},${item["partition"]["type"]}';
      var pname = asT<String?>(item["partition"]["title"]) ?? "";
      // 在首位插入顶级分类自身：让无子分区的一级分类(如聊天/音乐/文化)也能进入直播间
      categories_.insert(
        0,
        LiveArea(
          areaId: pid,
          typeName: pname,
          areaType: pid,
          areaName: pname,
          areaPic: "",
          platform: Sites.douyinSite,
        ),
      );
      var category = LiveCategory(children: categories_, id: pid, name: pname);
      categories.add(category);
    }
    return categories;
  }

  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    var ids = category.areaId?.split(',');
    var partitionId = ids?[0];
    var partitionType = ids?[1];

    String serverUrl = "https://live.douyin.com/webcast/web/partition/detail/room/v2/";
    var uri = Uri.parse(serverUrl).replace(
      scheme: "https",
      port: 443,
      queryParameters: {
        "aid": '6383',
        "app_name": "douyin_web",
        "live_id": '1',
        "device_platform": "web",
        "language": "zh-CN",
        "enter_from": "link_share",
        "cookie_enabled": "true",
        "screen_width": "1980",
        "screen_height": "1080",
        "browser_language": "zh-CN",
        "browser_platform": "Win32",
        "browser_name": "Edge",
        "browser_version": "125.0.0.0",
        "browser_online": "true",
        "count": '15',
        "offset": ((page - 1) * 15).toString(),
        "partition": partitionId,
        "partition_type": partitionType,
        "req_from": '2',
      },
    );
    var requestUrl = DouyinSign.getAbogusUrl(uri.toString(), kDefaultUserAgent);
    var result = await HttpClient.instance.getJson(requestUrl, header: await getRequestHeaders());
    var items = <LiveRoom>[];
    for (var item in result["data"]["data"]) {
      // 记录真实房间ID，进房时将 room_id_str 带上（贴近浏览器行为，降低风控）
      _webRidRoomIdCache[item["web_rid"].toString()] = item["room"]?["id_str"]?.toString() ?? "";
      var roomItem = LiveRoom(
        roomId: item["web_rid"],
        title: item["room"]["title"].toString(),
        cover: item["room"]["cover"]["url_list"][0].toString(),
        nick: item["room"]["owner"]["nickname"].toString(),
        liveStatus: LiveStatus.live,
        avatar: item["room"]["owner"]["avatar_thumb"]["url_list"][0].toString(),
        status: true,
        platform: Sites.douyinSite,
        area: item['tag_name'].toString(),
        watching: item["room"]?["room_view_stats"]?["display_value"].toString() ?? '',
      );
      items.add(roomItem);
    }
    return items;
  }

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    try {
      String serverUrl = "https://live.douyin.com/webcast/web/partition/detail/room/v2/";
      var uri = Uri.parse(serverUrl).replace(
        scheme: "https",
        port: 443,
        queryParameters: {
          "aid": '6383',
          "app_name": "douyin_web",
          "live_id": '1',
          "device_platform": "web",
          "language": "zh-CN",
          "enter_from": "link_share",
          "cookie_enabled": "true",
          "screen_width": "1980",
          "screen_height": "1080",
          "browser_language": "zh-CN",
          "browser_platform": "Win32",
          "browser_name": "Edge",
          "browser_version": "125.0.0.0",
          "browser_online": "true",
          "count": '20',
          "offset": ((page - 1) * 20).toString(),
          "partition": '720',
          "partition_type": '1',
          "req_from": '2',
        },
      );
      var requestUrl = DouyinSign.getAbogusUrl(uri.toString(), kDefaultUserAgent);
      var result = await HttpClient.instance.getJson(requestUrl, header: await getRequestHeaders());
      var items = <LiveRoom>[];
      for (var item in result["data"]["data"]) {
        // 记录真实房间ID，进房时将 room_id_str 带上（贴近浏览器行为，降低风控）
        _webRidRoomIdCache[item["web_rid"].toString()] = item["room"]?["id_str"]?.toString() ?? "";
        var roomItem = LiveRoom(
          roomId: item["web_rid"],
          title: item["room"]["title"].toString(),
          cover: item["room"]["cover"]["url_list"][0].toString(),
          nick: item["room"]["owner"]["nickname"].toString(),
          platform: Sites.douyinSite,
          area: item["tag_name"] ?? '热门推荐',
          avatar: item["room"]["owner"]["avatar_thumb"]["url_list"][0].toString(),
          watching: item["room"]?["room_view_stats"]?["display_value"].toString() ?? '',
          liveStatus: LiveStatus.live,
        );
        items.add(roomItem);
      }
      return items;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  @override
  Future<LiveRoom> getRoomDetail({required String platform, required String roomId}) async {
    if (roomId.length <= 16) {
      return await getRoomDetailByWebRid(roomId);
    }
    return await getRoomDetailByRoomId(roomId);
  }

  Future<LiveRoom> getRoomDetailByRoomId(String roomId) async {
    // 读取房间信息
    var roomData = await _getRoomDataByRoomId(roomId);

    // 通过房间信息获取WebRid
    var webRid = roomData["data"]["room"]["owner"]["web_rid"].toString();

    // 读取用户唯一ID，用于弹幕连接
    // 似乎这个参数不是必须的，先随机生成一个
    //var userUniqueId = await _getUserUniqueId(webRid);
    var userUniqueId = generateRandomNumber(12).toString();

    var room = roomData["data"]["room"];
    var owner = room["owner"];

    var status = asT<int?>(room["status"]) ?? 0;

    // roomId是一次性的，用户每次重新开播都会生成一个新的roomId
    // 所以如果roomId对应的直播间状态不是直播中，就通过webRid获取直播间信息
    if (status == 4) {
      var result = await getRoomDetailByWebRid(webRid);
      return result;
    }

    var roomStatus = status == 2;
    // 主要是为了获取cookie,用于弹幕websocket连接
    var headers = await getRequestHeaders();

    return LiveRoom(
      roomId: webRid,
      title: room["title"].toString(),
      cover: roomStatus ? room["cover"]["url_list"][0].toString() : "",
      nick: owner["nickname"].toString(),
      avatar: owner["avatar_thumb"]["url_list"][0].toString(),
      watching: roomStatus ? room["room_view_stats"]["display_value"].toString() : "",
      status: roomStatus,
      link: "https://live.douyin.com/$webRid",
      platform: Sites.douyinSite,
      area: '',
      userId: owner["sec_uid"].toString(),
      liveStatus: roomStatus ? LiveStatus.live : LiveStatus.offline,
      introduction: owner["signature"].toString(),
      notice: "",
      danmakuData: DouyinDanmakuArgs(webRid: webRid, roomId: roomId, userId: userUniqueId, cookie: headers["cookie"]),
      data: room["stream_url"],
    );
  }

  /// 通过WebRid获取直播间信息
  /// - [webRid] 直播间RID
  /// - 返回直播间信息
  /// - 容错策略：API(abogus签名) → 强刷cookie重试API(防偶发风控) → HTML页面解析兜底
  Future<LiveRoom> getRoomDetailByWebRid(String webRid) async {
    // 第一级：API（含 abogus 签名）。成功即返回（offline 也是明确状态，无需重试）
    try {
      var result = await _getRoomDetailByWebRidApi(webRid);
      return result;
    } catch (e) {
      CoreLog.error("douyin API取房间失败: $e");
    }
    // 第二级：强制刷新 cookie 后重试 API（API异常多为过期cookie/旧msToken导致的风控，换新会话即恢复）
    try {
      await _refreshDynamicCookie(force: true);
      var result = await _getRoomDetailByWebRidApi(webRid);
      return result;
    } catch (e) {
      CoreLog.error("douyin API重试取房间失败: $e");
    }
    // 第三级：HTML 页面解析兜底（浏览器同款数据源）
    try {
      return await _getRoomDetailByWebRidHtml(webRid);
    } catch (e) {
      CoreLog.error("douyin HTML兜底取房间失败: $e");
    }
    return LiveRoom(
      roomId: webRid,
      platform: Sites.douyinSite,
      liveStatus: LiveStatus.unknown,
    );
  }

  /// 通过WebRid访问直播间API，从API中获取直播间信息
  /// - [webRid] 直播间RID
  /// - 返回直播间信息
  Future<LiveRoom> _getRoomDetailByWebRidApi(String webRid) async {
    // 读取房间信息
    var data = await _getRoomDataByApi(webRid);

    var roomData = data["data"][0];
    var userData = data["user"];
    var roomId = roomData["id_str"].toString();

    // 读取用户唯一ID，用于弹幕连接
    // 似乎这个参数不是必须的，先随机生成一个
    //var userUniqueId = await _getUserUniqueId(webRid);
    var userUniqueId = generateRandomNumber(12).toString();

    var owner = roomData["owner"];

    var roomStatus = (asT<int?>(roomData["status"]) ?? 0) == 2;

    // 主要是为了获取cookie,用于弹幕websocket连接
    var headers = await getRequestHeaders();
    return LiveRoom(
      roomId: webRid,
      title: roomData["title"].toString(),
      cover: roomStatus ? roomData["cover"]["url_list"][0].toString() : "",
      nick: roomStatus ? owner["nickname"].toString() : userData["nickname"].toString(),
      avatar: roomStatus
          ? owner["avatar_thumb"]["url_list"][0].toString()
          : userData["avatar_thumb"]["url_list"][0].toString(),
      watching: roomStatus ? roomData["room_view_stats"]["display_value"].toString() : "",
      status: roomStatus,
      liveStatus: roomStatus ? LiveStatus.live : LiveStatus.offline,
      link: "https://live.douyin.com/$webRid",
      platform: Sites.douyinSite,
      area: '',
      introduction: owner?["signature"]?.toString() ?? "",
      notice: "",
      danmakuData: DouyinDanmakuArgs(webRid: webRid, roomId: roomId, userId: userUniqueId, cookie: headers["cookie"]),
      data: roomStatus ? roomData["stream_url"] : {},
    );
  }

  /// 通过WebRid访问直播间网页，从网页HTML中获取直播间信息
  /// - [webRid] 直播间RID
  /// - 返回直播间信息
  Future<LiveRoom> _getRoomDetailByWebRidHtml(String roomId) async {
    var detail = await _getRoomDataByHtml(roomId);
    var webRid = roomId;

    var realRoomId = detail["roomStore"]["roomInfo"]["room"]["id_str"].toString();
    var userUniqueId = detail["userStore"]["odin"]["user_unique_id"].toString();
    var roomInfo = detail["roomStore"]["roomInfo"]["room"];
    var owner = roomInfo["owner"];
    var anchor = detail["roomStore"]["roomInfo"]["anchor"];
    var roomStatus = (asT<int?>(roomInfo["status"]) ?? 0) == 2;

    // 主要是为了获取cookie,用于弹幕websocket连接
    var headers = await getRequestHeaders();

    return LiveRoom(
      roomId: roomId,
      title: roomInfo["title"].toString(),
      cover: roomStatus ? roomInfo["cover"]["url_list"][0].toString() : "",
      nick: roomStatus ? owner["nickname"].toString() : anchor["nickname"].toString(),
      avatar: roomStatus
          ? owner["avatar_thumb"]["url_list"][0].toString()
          : anchor["avatar_thumb"]["url_list"][0].toString(),
      watching: roomInfo?["room_view_stats"]?["display_value"].toString() ?? '',
      liveStatus: roomStatus ? LiveStatus.live : LiveStatus.offline,
      link: "https://live.douyin.com/$webRid",
      area: '',
      status: roomStatus,
      platform: Sites.douyinSite,
      userId: anchor["sec_uid"].toString(),
      introduction: roomInfo["title"].toString(),
      notice: "",
      danmakuData: DouyinDanmakuArgs(
        webRid: webRid,
        roomId: realRoomId,
        userId: userUniqueId,
        cookie: headers["cookie"],
      ),
      data: roomStatus ? roomInfo["stream_url"] : {},
    );
  }

  /// 读取用户的唯一ID
  /// - [webRid] 直播间RID
  // ignore: unused_element
  Future<String> _getUserUniqueId(String webRid) async {
    try {
      var webInfo = await _getRoomDataByHtml(webRid);
      return webInfo["userStore"]["odin"]["user_unique_id"].toString();
    } catch (e) {
      return generateRandomNumber(12).toString();
    }
  }

  /// 进入直播间前需要先获取cookie
  /// - [webRid] 直播间RID
  Future<String> _getWebCookie(String webRid) async {
    // 优先复用全局缓存的动态 cookie（浏览器会话式，长期有效），避免每次都 HEAD 增加风控请求数
    await _refreshDynamicCookie();
    if (_dynamicCookie.isNotEmpty) {
      return _dynamicCookie;
    }
    var headResp = await HttpClient.instance.head("https://live.douyin.com/$webRid", header: headers);
    var dyCookie = "";
    headResp.headers["set-cookie"]?.forEach((element) {
      var cookie = element.split(";")[0];
      if (cookie.contains("ttwid")) {
        dyCookie += "$cookie;";
      }
      if (cookie.contains("__ac_nonce")) {
        dyCookie += "$cookie;";
      }
      if (cookie.contains("msToken")) {
        dyCookie += "$cookie;";
      }
    });
    return dyCookie;
  }

  /// 通过webRid获取直播间Web信息
  /// - [webRid] 直播间RID
  Future<Map> _getRoomDataByHtml(String webRid) async {
    var dyCookie = await _getWebCookie(webRid);
    var result = await HttpClient.instance.getText(
      "https://live.douyin.com/$webRid",
      queryParameters: {},
      header: {
        "Authority": kDefaultAuthority,
        "Referer": kDefaultReferer,
        "Cookie": dyCookie,
        "User-Agent": kDefaultUserAgent,
      },
    );

    var renderData = RegExp(r'\{\\"state\\":\{\\"appStore.*?\]\\n').firstMatch(result)?.group(0) ?? "";
    var str = renderData.trim().replaceAll('\\"', '"').replaceAll(r"\\", r"\").replaceAll(']\\n', "");

    var renderDataJson = json.decode(str);
    return renderDataJson["state"];
  }

  /// 通过webRid获取直播间Web信息
  /// - [webRid] 直播间RID
  Future<Map> _getRoomDataByApi(String webRid) async {
    String serverUrl = "https://live.douyin.com/webcast/room/web/enter/";
    var uri = Uri.parse(serverUrl).replace(
      scheme: "https",
      port: 443,
      queryParameters: {
        "aid": '6383',
        "app_name": "douyin_web",
        "live_id": '1',
        "device_platform": "web",
        "enter_from": "link_share",
        "web_rid": webRid,
        "room_id_str": _webRidRoomIdCache[webRid] ?? "",
        "enter_source": "",
        "Room-Enter-User-Login-Ab": '0',
        "is_need_double_stream": 'false',
        "cookie_enabled": 'true',
        "screen_width": '1980',
        "screen_height": '1080',
        "browser_language": "zh-CN",
        "browser_platform": "Win32",
        "browser_name": "Edge",
        "browser_version": "125.0.0.0",
      },
    );
    var requestUrl = DouyinSign.getAbogusUrl(uri.toString(), kDefaultUserAgent);
    var requestHeader = await getRequestHeaders();
    final response = await HttpClient.instance.get(requestUrl, header: requestHeader);

    // 提取服务端下发的合法 msToken 并缓存：后续请求携带它，风控分数显著低于随机串
    final msTokenHeader = response.headers.value("x-ms-token");
    if (msTokenHeader != null && msTokenHeader.isNotEmpty) {
      _serverMsToken = msTokenHeader;
      // query 参数也复用服务端 token（与浏览器同一会话复用行为一致）
      DouyinSign.msTokenOverride = msTokenHeader;
    }
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data["data"];
    }
    throw Exception("douyin enter API 响应异常(可能被风控): $data");
  }

  /// 通过roomId获取直播间信息
  /// - [roomId] 直播间ID
  Future<Map> _getRoomDataByRoomId(String roomId) async {
    var result = await HttpClient.instance.getJson(
      'https://webcast.amemv.com/webcast/room/reflow/info/',
      queryParameters: {
        "type_id": 0,
        "live_id": 1,
        "room_id": roomId,
        "sec_user_id": "",
        "version_code": "99.99.99",
        "app_id": 6383,
      },
      header: await getRequestHeaders(),
    );
    return result;
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    final qualities = <LivePlayQuality>[];
    final data = detail.data;
    if (data == null || data.isEmpty) return qualities;

    try {
      // ---------- 新结构：live_core_sdk_data.pull_data ----------
      final coreSdk = data["live_core_sdk_data"];
      if (coreSdk is Map) {
        final pullData = coreSdk["pull_data"];
        if (pullData is Map) {
          final qulityList = (pullData["options"] is Map
                  ? pullData["options"]["qualities"]
                  : null) as List? ??
              [];
          final streamData = pullData["stream_data"]?.toString() ?? '';

          var qualityData = <String, dynamic>{};
          var parseOk = false;
          if (streamData.startsWith('{')) {
            try {
              final decoded = json.decode(streamData);
              final dd = decoded is Map ? decoded["data"] : null;
              if (dd is Map) {
                qualityData = dd.cast<String, dynamic>();
                parseOk = true;
              }
            } catch (e) {
              CoreLog.error("douyin stream_data JSON解析失败: $e");
            }
          }

          if (parseOk) {
            for (var quality in qulityList) {
              List<String> urls = [];
              final key = quality["sdk_key"];
              if (key == null) continue;
              final entry = qualityData[key];
              if (entry is Map) {
                final main = entry["main"];
                if (main is Map) {
                  final flvUrl = main["flv"]?.toString();
                  if (flvUrl != null && flvUrl.isNotEmpty) urls.add(flvUrl);
                  final hlsUrl = main["hls"]?.toString();
                  if (hlsUrl != null && hlsUrl.isNotEmpty) urls.add(hlsUrl);
                }
              }
              if (urls.isNotEmpty) {
                qualities.add(LivePlayQuality(
                  quality: quality["name"]?.toString() ?? '',
                  sort: (quality["level"] as num?)?.toInt() ?? 0,
                  data: urls,
                ));
              }
            }
          } else if (data["flv_pull_url"] is Map) {
            // ---------- 老结构：flv_pull_url / hls_pull_url_map ----------
            final flvList = (data["flv_pull_url"] as Map).values.cast<String>().toList();
            final hlsList = (data["hls_pull_url_map"] as Map).values.cast<String>().toList();
            for (var quality in qulityList) {
              int level = (quality["level"] as num?)?.toInt() ?? 0;
              List<String> urls = [];
              var flvIndex = flvList.length - level;
              if (flvIndex >= 0 && flvIndex < flvList.length) {
                urls.add(flvList[flvIndex]);
              }
              var hlsIndex = hlsList.length - level;
              if (hlsIndex >= 0 && hlsIndex < hlsList.length) {
                urls.add(hlsList[hlsIndex]);
              }
              if (urls.isNotEmpty) {
                qualities.add(LivePlayQuality(
                  quality: quality["name"]?.toString() ?? '',
                  sort: level,
                  data: urls,
                ));
              }
            }
          }
        }
      }

      // ---------- 最终兜底：无 live_core_sdk_data 时直接读 flv_pull_url 等 ----------
      if (qualities.isEmpty && data["flv_pull_url"] is Map) {
        final flvMap = data["flv_pull_url"] as Map;
        final hlsMap = data["hls_pull_url_map"] as Map? ?? {};
        final names = {'FULL_HD1': 4, 'HD1': 3, 'SD1': 2, 'SD2': 1};
        flvMap.forEach((k, v) {
          final urls = <String>[];
          final flv = v?.toString();
          if (flv != null && flv.isNotEmpty) urls.add(flv);
          final hls = hlsMap[k]?.toString();
          if (hls != null && hls.isNotEmpty) urls.add(hls);
          if (urls.isNotEmpty) {
            final level = names[k?.toString()] ?? 0;
            qualities.add(LivePlayQuality(
              quality: k?.toString() ?? '',
              sort: level,
              data: urls,
            ));
          }
        });
      }
    } catch (e) {
      CoreLog.error("douyin getPlayQualites 解析失败: $e");
    }

    qualities.sort((a, b) => b.sort.compareTo(a.sort));
    return qualities;
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    return quality.data;
  }

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    String serverUrl = "https://www.douyin.com/aweme/v1/web/live/search/";
    var uri = Uri.parse(serverUrl).replace(
      scheme: "https",
      port: 443,
      queryParameters: {
        "device_platform": "webapp",
        "aid": "6383",
        "channel": "channel_pc_web",
        "search_channel": "aweme_live",
        "keyword": keyword,
        "search_source": "switch_tab",
        "query_correct_type": "1",
        "is_filter_search": "0",
        "from_group_id": "",
        "offset": ((page - 1) * 10).toString(),
        "count": "10",
        "pc_client_type": "1",
        "version_code": "170400",
        "version_name": "17.4.0",
        "cookie_enabled": "true",
        "screen_width": "1980",
        "screen_height": "1080",
        "browser_language": "zh-CN",
        "browser_platform": "Win32",
        "browser_name": "Edge",
        "browser_version": "125.0.0.0",
        "browser_online": "true",
        "engine_name": "Blink",
        "engine_version": "125.0.0.0",
        "os_name": "Windows",
        "os_version": "10",
        "cpu_core_num": "12",
        "device_memory": "8",
        "platform": "PC",
        "downlink": "10",
        "effective_type": "4g",
        "round_trip_time": "100",
        "webid": "7382872326016435738",
      },
    );
    var requlestUrl = uri.toString();
    var headResp = await getRequestHeaders();
    var dyCookie = headResp['cookie'];
    var result = await HttpClient.instance.getJson(
      requlestUrl,
      queryParameters: {},
      header: {
        "Authority": 'www.douyin.com',
        'accept': 'application/json, text/plain, */*',
        'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'cookie': dyCookie,
        'priority': 'u=1, i',
        'referer': 'https://www.douyin.com/search/${Uri.encodeComponent(keyword)}?type=live',
        'sec-ch-ua': '"Microsoft Edge";v="125", "Chromium";v="125", "Not.A/Brand";v="24"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        'sec-fetch-dest': 'empty',
        'sec-fetch-mode': 'cors',
        'sec-fetch-site': 'same-origin',
        'user-agent': DouyinRequestParams.kDefaultUserAgent,
      },
    );
    if (result == "" || result == 'blocked') {
      throw Exception("抖音直播搜索被限制，请稍后再试");
    }
    var items = <LiveRoom>[];
    for (var item in result["data"] ?? []) {
      var itemData = json.decode(item["lives"]["rawdata"].toString());
      var roomStatus = (asT<int?>(itemData["status"]) ?? 0) == 2;
      var roomItem = LiveRoom(
        roomId: itemData["owner"]["web_rid"].toString(),
        title: itemData["title"].toString(),
        cover: itemData["cover"]["url_list"][0].toString(),
        nick: itemData["owner"]["nickname"].toString(),
        platform: Sites.douyinSite,
        avatar: itemData["owner"]["avatar_thumb"]["url_list"][0].toString(),
        liveStatus: roomStatus ? LiveStatus.live : LiveStatus.offline,
        area: '',
        status: roomStatus,
        watching: itemData["stats"]["total_user_str"].toString(),
      );
      items.add(roomItem);
    }
    return items;
  }

  @override
  Future<List<LiveAnchorItem>> searchAnchors(String keyword, {int page = 1, int pageSize = 30}) async {
    throw Exception("抖音暂不支持搜索主播，请直接搜索直播间");
  }

  @override
  Future<bool> getLiveStatus({required String platform, required String roomId}) async {
    var result = await getRoomDetail(roomId: roomId, platform: platform);
    return result.status!;
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({required String roomId}) {
    return Future.value(<LiveSuperChatMessage>[]);
  }

  //生成指定长度的16进制随机字符串
  String generateRandomString(int length) {
    var random = math.Random.secure();
    var values = List<int>.generate(length, (i) => random.nextInt(16));
    StringBuffer stringBuffer = StringBuffer();
    for (var item in values) {
      stringBuffer.write(item.toRadixString(16));
    }
    return stringBuffer.toString();
  }

  // 生成随机的数字
  int generateRandomNumber(int length) {
    var random = math.Random.secure();
    var values = List<int>.generate(length, (i) => random.nextInt(10));
    StringBuffer stringBuffer = StringBuffer();
    for (var item in values) {
      stringBuffer.write(item);
    }
    return int.tryParse(stringBuffer.toString()) ?? math.Random().nextInt(1000000000);
  }
}