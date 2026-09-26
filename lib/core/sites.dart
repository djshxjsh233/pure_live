import 'site/yy/yy_site.dart';
import 'site/kick/kick_site.dart';
import 'site/bigo/bigo_site.dart';
import 'site/soop/soop_site.dart';
import 'site/huya/huya_site.dart';
import 'interface/live_site.dart';
import 'site/fc2live/fc2_site.dart';
import 'site/tting/tting_site.dart';
import 'site/acfun/acfun_site.dart';
import 'site/douyu/douyu_site.dart';
import 'site/douyin/douyin_site.dart';
import 'site/openrec/openrec_site.dart';
import 'site/huajiao/huajiao_site.dart';
import 'site/goodgame/goodgame_site.dart';
import 'site/showroom/showroom_site.dart';
import 'site/kilakila/kilakila_site.dart';
import 'site/looklive/look_live_site.dart';

import 'package:pure_live/common/index.dart';

import 'site/taobaolive/taobao_live_site.dart';
import 'site/xiaohongshu/xiaohongshu_site.dart';

import 'package:pure_live/core/site/cc/cc_site.dart';


import 'package:pure_live/core/site/iptv/iptv_site.dart';
import 'package:pure_live/core/site/twitch/twitch_site.dart';
import 'package:pure_live/core/site/kuaishou/kuaishou_site.dart';
import 'package:pure_live/core/site/bilibili/bilibili_site.dart';

class Sites {
  static const String allSite = "all";
  static const String bilibiliSite = "bilibili";
  static const String douyuSite = "douyu";
  static const String huyaSite = "huya";
  static const String douyinSite = "douyin";
  static const String kuaishouSite = "kuaishou";
  static const String ccSite = "cc";
  static const String iptvSite = "iptv";
  static const String twitchSite = "twitch";
  static const String soopSite = 'soop';
  static const String yySite = 'yy';
  static const String acfunSite = 'acfun';
  static const String kilakilaSite = 'kilakila';
  static const String huajiaoSite = 'huajiao';
  static const String openrecSite = 'openrec';
  static const String ttingSite = 'ttinglive';
  static const String xiaohongshuSite = 'xiaohongshu';
  static const String showroomSite = 'showroom';
  static const String kickSite = 'kick';
  static const String bigoSite = 'bigo';
  static const String goodGameSite = 'goodgame';
  static const String fc2LiveSite = 'fc2live';
  static const String taobaoLiveSite = 'taobaolive';
  static const String lookLiveSite = 'looklive';

  static const Set<String> supportedSiteIds = {
    bilibiliSite,
    douyuSite,
    huyaSite,
    douyinSite,
    kuaishouSite,
    ccSite,
    twitchSite,
    soopSite,
    yySite,
    acfunSite,
    kilakilaSite,
    huajiaoSite,
    openrecSite,
    ttingSite,
    xiaohongshuSite,
    showroomSite,
    kickSite,
    bigoSite,
    goodGameSite,
    fc2LiveSite,
    taobaoLiveSite,
    lookLiveSite,
    iptvSite,
  };

  /// Root directory for all platform artwork.
  static const String _assetRoot = 'assets/images';

  /// Keep all platform logos in one place.
  ///
  /// Every supported platform must resolve to its own asset here; the generic
  /// `logo.png` is only the safety net in [logoForId] for future additions
  /// that have not received artwork yet.
  static const Map<String, String> _logos = {
    bilibiliSite: '$_assetRoot/bilibili_2.png',
    douyuSite: '$_assetRoot/douyu.png',
    huyaSite: '$_assetRoot/huya.png',
    douyinSite: '$_assetRoot/douyin.png',
    kuaishouSite: '$_assetRoot/kuaishou.png',
    ccSite: '$_assetRoot/cc.png',
    iptvSite: '$_assetRoot/iptv.png',
    twitchSite: '$_assetRoot/twitch.png',
    soopSite: '$_assetRoot/soop.png',
    yySite: '$_assetRoot/yy.png',
    acfunSite: '$_assetRoot/acfun.png',
    kilakilaSite: '$_assetRoot/kilakila.png',
    huajiaoSite: '$_assetRoot/huajiao.png',
    openrecSite: '$_assetRoot/openrec.png',
    ttingSite: '$_assetRoot/ttinglive.png',
    xiaohongshuSite: '$_assetRoot/xiaohongshu.png',
    showroomSite: '$_assetRoot/showroom.png',
    kickSite: '$_assetRoot/kick.png',
    goodGameSite: '$_assetRoot/goodgame.png',
    fc2LiveSite: '$_assetRoot/fc2.png',
    taobaoLiveSite: '$_assetRoot/taobao.png',
    lookLiveSite: '$_assetRoot/look.png',
    bigoSite: '$_assetRoot/bigo.png',
  };

  static bool isSupported(String id) => supportedSiteIds.contains(id.trim().toLowerCase());

  /// Read-only artwork lookup for frequently rebuilt room and multiview UI.
  /// A badge must not allocate a platform adapter just to obtain its asset.
  static String logoForId(String id) {
    final normalizedId = id.trim().toLowerCase();
    if (!supportedSiteIds.contains(normalizedId)) throw StateError('Unsupported live site: $normalizedId');
    return _logos[normalizedId] ?? '$_assetRoot/logo.png';
  }

  /// Create a single platform adapter.
  ///
  /// Keeping construction in one switch prevents `supportSites`,
  /// `availableSites` and `of` from drifting apart when a new platform
  /// is added, and guarantees every site picks up its logo through
  /// [logoForId] instead of hard-coding asset paths in three places.
  static Site _createSite(String id) {
    final normalizedId = id.trim().toLowerCase();
    return switch (normalizedId) {
      bilibiliSite => Site(
        id: bilibiliSite,
        name: i18n("site_bilibili"),
        logo: logoForId(bilibiliSite),
        liveSite: BiliBiliSite(),
      ),
      douyuSite => Site(id: douyuSite, name: i18n("site_douyu"), logo: logoForId(douyuSite), liveSite: DouyuSite()),
      huyaSite => Site(id: huyaSite, name: i18n("site_huya"), logo: logoForId(huyaSite), liveSite: HuyaSite()),
      douyinSite => Site(
        id: douyinSite,
        name: i18n("site_douyin"),
        logo: logoForId(douyinSite),
        liveSite: DouyinSite(),
      ),
      kuaishouSite => Site(
        id: kuaishouSite,
        name: i18n("site_kuaishou"),
        logo: logoForId(kuaishouSite),
        liveSite: KuaishowSite(),
      ),
      ccSite => Site(id: ccSite, name: i18n("site_cc"), logo: logoForId(ccSite), liveSite: CCSite()),
      twitchSite => Site(
        id: twitchSite,
        name: i18n("site_twitch"),
        logo: logoForId(twitchSite),
        liveSite: TwitchSite(),
      ),
      soopSite => Site(id: soopSite, name: i18n("site_soop"), logo: logoForId(soopSite), liveSite: SoopSite()),
      yySite => Site(id: yySite, name: i18n("site_yy"), logo: logoForId(yySite), liveSite: YYSite()),
      acfunSite => Site(id: acfunSite, name: i18n('site_acfun'), logo: logoForId(acfunSite), liveSite: AcfunSite()),
      iptvSite => Site(id: iptvSite, name: i18n("site_iptv"), logo: logoForId(iptvSite), liveSite: IptvSite()),
      kilakilaSite => Site(
        id: kilakilaSite,
        name: i18n('site_kilakila'),
        logo: logoForId(kilakilaSite),
        liveSite: KilakilaSite(),
      ),
      huajiaoSite => Site(
        id: huajiaoSite,
        name: i18n('site_huajiao'),
        logo: logoForId(huajiaoSite),
        liveSite: HuajiaoSite(),
      ),
      openrecSite => Site(
        id: openrecSite,
        name: 'mellow-fan (OPENREC)',
        logo: logoForId(openrecSite),
        liveSite: OpenrecSite(),
      ),
      ttingSite => Site(id: ttingSite, name: 'FLEX TV (TTingLive)', logo: logoForId(ttingSite), liveSite: TtingSite()),
      xiaohongshuSite => Site(
        id: xiaohongshuSite,
        name: i18n('site_xiaohongshu'),
        logo: logoForId(xiaohongshuSite),
        liveSite: XiaohongshuSite(),
      ),
      showroomSite => Site(
        id: showroomSite,
        name: i18n('site_showroom'),
        logo: logoForId(showroomSite),
        liveSite: ShowroomSite(),
      ),
      kickSite => Site(id: kickSite, name: i18n('site_kick'), logo: logoForId(kickSite), liveSite: KickSite()),
      bigoSite => Site(id: bigoSite, name: i18n('site_bigo'), logo: logoForId(bigoSite), liveSite: BigoSite()),
      goodGameSite => Site(
        id: goodGameSite,
        name: i18n('site_goodgame'),
        logo: logoForId(goodGameSite),
        liveSite: GoodGameSite(),
      ),
      fc2LiveSite => Site(
        id: fc2LiveSite,
        name: i18n('site_fc2live'),
        logo: logoForId(fc2LiveSite),
        liveSite: Fc2Site(),
      ),
      taobaoLiveSite => Site(
        id: taobaoLiveSite,
        name: i18n('site_taobaolive'),
        logo: logoForId(taobaoLiveSite),
        liveSite: TaobaoLiveSite(),
      ),
      lookLiveSite => Site(
        id: lookLiveSite,
        name: i18n('site_looklive'),
        logo: logoForId(lookLiveSite),
        liveSite: LookLiveSite(),
      ),
      _ => throw StateError('Unsupported live site: $normalizedId'),
    };
  }

  /// Build the complete supported-site list.
  ///
  /// The list is cached because platform adapters can contain session,
  /// authentication or request-related state. Recreating them every time
  /// `supportSites` is accessed would unnecessarily discard that state.
  static final List<Site> _supportedSites = List<Site>.unmodifiable([
    for (final id in [
      bilibiliSite,
      douyuSite,
      huyaSite,
      douyinSite,
      kuaishouSite,
      ccSite,
      twitchSite,
      soopSite,
      yySite,
      acfunSite,
      kilakilaSite,
      huajiaoSite,
      openrecSite,
      ttingSite,
      xiaohongshuSite,
      showroomSite,
      kickSite,
      bigoSite,
      goodGameSite,
      fc2LiveSite,
      taobaoLiveSite,
        lookLiveSite,
      iptvSite,
    ])
      _createSite(id),
  ]);

  static List<Site> get supportSites => _supportedSites;

  static Site of(String id) {
    final normalizedId = id.trim().toLowerCase();
    // Do not construct every platform adapter for a single lookup. Favourite
    // verification performs this operation for every saved room; the previous
    // list scan allocated nine adapters per card and also discarded platform
    // session caches immediately afterwards. Reusing the cached adapter keeps
    // both allocations and platform session state intact.
    for (final site in _supportedSites) {
      if (site.id == normalizedId) return site;
    }
    return _createSite(normalizedId);
  }

  List<Site> availableSites({bool containsAll = false}) {
    final List<String> savedIds = SettingsService.to.fav.hotAreasList.v;
    final supportedById = {for (final site in supportSites) site.id: site};
    final List<Site> result = [];
    final seen = <String>{};
    for (String rawId in savedIds) {
      final id = rawId.trim().toLowerCase();
      if (!seen.add(id)) continue;
      final match = supportedById[id];
      if (match != null) {
        result.add(match);
      }
    }
    if (containsAll) {
      result.insert(0, Site(id: allSite, name: i18n("site_all"), logo: "$_assetRoot/all.png", liveSite: LiveSite()));
    }
    return result;
  }
}

class Site {
  final String id;
  final String _fallbackName;
  final String logo;
  final LiveSite liveSite;

  Site({required this.id, required this.liveSite, required this.logo, required String name}) : _fallbackName = name;

  /// Resolve registry labels when they are painted instead of freezing the
  /// locale that happened to be active when an adapter was constructed.
  /// Popular and search controllers deliberately retain their [Site]
  /// instances so pagination/session state stays stable; the label must still
  /// follow an in-app language change without rebuilding those adapters.
  String get name {
    final normalizedId = id.trim().toLowerCase();
    if (normalizedId != Sites.allSite && !Sites.isSupported(normalizedId)) return _fallbackName;
    return i18nOr('site_$normalizedId', _fallbackName);
  }
}
