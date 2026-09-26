import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/danmaku/douyin_danmaku.dart';
import 'package:pure_live/core/danmaku/huya_danmaku.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/core/site/goodgame/goodgame_link.dart';
import 'package:pure_live/core/site/fc2live/fc2_link.dart';
import 'package:pure_live/core/site/taobaolive/taobao_live_link.dart';
import 'package:pure_live/core/site/looklive/look_live_link.dart';
import 'package:url_launcher/url_launcher_string.dart';

enum RoomExternalOpenResult { opened, unavailable, failed, cancelled }

/// Resolved once per user action. Never passes a relative/empty URL to the OS.
class RoomExternalTarget {
  const RoomExternalTarget({required this.web, this.native});
  final String web;
  final String? native;
}

typedef RoomExternalLauncher = Future<bool> Function(String url);

class RoomExternalOpener {
  static RoomExternalTarget? _official(String Function() build) {
    try {
      return RoomExternalTarget(web: build());
    } on FormatException {
      return null;
    }
  }

  static String? _id(String? value) {
    final id = value?.trim();
    if (id == null || id.isEmpty || id == '.' || id == '..' || RegExp(r'[\s\x00-\x1f/\\?#%]').hasMatch(id)) {
      return null;
    }
    return id;
  }

  static RoomExternalTarget? resolve(String site, LiveRoom room) {
    final id = _id(room.roomId);
    if (id == null) return null;
    final path = Uri.encodeComponent(id);
    switch (site) {
      case Sites.goodGameSite:
        final reference = GoodGameLink.parseReference(id);
        if (reference == null) return null;
        return _official(
          () => reference.kind == GoodGameLinkKind.player
              ? Uri.https('goodgame.ru', '/player', {'src': reference.value}).toString()
              : GoodGameLink.channelUrl(reference.value),
        );
      case Sites.fc2LiveSite:
        return _official(() => Fc2Link.channelUrl(id));
      case Sites.taobaoLiveSite:
        return _official(() => TaobaoLiveLink.watchUrl(id));
      case Sites.lookLiveSite:
        return _official(() => LookLiveLink.watchUrl(id));
      case Sites.bilibiliSite:
        return RoomExternalTarget(web: 'https://live.bilibili.com/$path', native: 'bilibili://live/$path');
      case Sites.douyinSite:
        final args = room.danmakuData;
        final webId = args is DouyinDanmakuArgs ? _id(args.webRid) ?? id : id;
        final nativeId = args is DouyinDanmakuArgs ? _id(args.roomId) : null;
        return RoomExternalTarget(
          web: 'https://live.douyin.com/${Uri.encodeComponent(webId)}',
          native: nativeId == null ? null : 'snssdk1128://webcast_room?room_id=${Uri.encodeComponent(nativeId)}',
        );
      case Sites.huyaSite:
        final args = room.danmakuData;
        return RoomExternalTarget(
          web: 'https://www.huya.com/$path',
          // Keep the existing native protocol mapping; missing optional chat
          // metadata must not prevent the independent official webpage action.
          native: args is HuyaDanmakuArgs && args.subSid > 0
              ? 'yykiwi://homepage/index.html?banneraction=https%3A%2F%2Fdiy-front.cdn.huya.com%2Fzt%2Ffrontpage%2Fcc%2Fupdate.html%3Fhyaction%3Dlive%26channelid%3D${args.subSid}%26subid%3D${args.subSid}%26liveuid%3D${args.subSid}%26screentype%3D1%26sourcetype%3D0%26fromapp%3Dhuya_wap%252Fclick%252Fopen_app_guide%26&fromapp=huya_wap/click/open_app_guide'
              : null,
        );
      case Sites.douyuSite:
        return RoomExternalTarget(
          web: 'https://www.douyu.com/$path',
          native: 'douyulink://?type=90001&schemeUrl=douyuapp%3A%2F%2Froom%3FliveType%3D0%26rid%3D$path',
        );
      case Sites.kuaishouSite:
        final stream = room.link?.trim() ?? '';
        final encoded = Uri.encodeQueryComponent(stream);
        return RoomExternalTarget(
          web: 'https://live.kuaishou.com/u/$path',
          native: stream.isEmpty
              ? null
              : 'kwai://liveaggregatesquare?liveStreamId=$encoded&recoStreamId=$encoded&recoLiveStreamId=$encoded&liveSquareSource=28&path=/rest/n/live/feed/sharePage/slide/more&mt_product=H5_OUTSIDE_CLIENT_SHARE',
        );
      default:
        // IPTV has media locations, not an official room webpage. Never forward
        // an arbitrary imported link or an empty string as a shell target.
        return null;
    }
  }

  static Future<bool> _launch(String url) => launchUrlString(url, mode: LaunchMode.externalApplication);

  static Future<RoomExternalOpenResult> open({
    required String site,
    required LiveRoom room,
    required bool android,
    RoomExternalLauncher? launch,
    bool Function()? isCurrent,
    void Function()? onBrowserFallback,
  }) async {
    bool current() => isCurrent?.call() ?? true;
    if (!current()) return RoomExternalOpenResult.cancelled;
    final target = resolve(site, room);
    if (target == null) return RoomExternalOpenResult.unavailable;
    final launcher = launch ?? _launch;
    Future<bool> attempt(String url) async {
      try {
        return await launcher(url);
      } catch (_) {
        // Never log targets; they may include platform share parameters.
        return false;
      }
    }

    final native = android ? target.native : null;
    if (native != null && native != target.web) {
      final opened = await attempt(native);
      if (!current()) return RoomExternalOpenResult.cancelled;
      if (opened) return RoomExternalOpenResult.opened;
      onBrowserFallback?.call();
      if (!current()) return RoomExternalOpenResult.cancelled;
    }
    final opened = await attempt(target.web);
    if (!current()) return RoomExternalOpenResult.cancelled;
    return opened ? RoomExternalOpenResult.opened : RoomExternalOpenResult.failed;
  }
}
