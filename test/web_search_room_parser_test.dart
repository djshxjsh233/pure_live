import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/modules/search/web_search_room_parser.dart';
import 'package:pure_live/common/utils/live_url_tool.dart';

void main() {

  test('ignores search/navigation pages and lookalike domains', () {
    const urls = [
      'https://www.huya.com/search?hsk=test',
      'https://www.twitch.tv/directory',
      'https://www.douyu.com/topic/something',
      'https://live.kuaishou.com/search?keyword=test',
      'https://live.bilibili.com/p/eden/area-tags',
      'https://www.yy.com/search-test',
      'https://www.huya.com.evil.example/1234',
      'javascript:alert(1)',
      'https://www.acfun.cn/u/42',
      'https://www.acfun.cn/v/ac42',
      'https://live.acfun.cn/live/0',
      'https://live.acfun.cn/live/42/extra',
      'https://live.acfun.cn.evil.example/live/42',
      'https://secret@live.acfun.cn/live/42',
      'https://www.xiaohongshu.com/explore/1234567890123456789',
      'https://www.xiaohongshu.com/livestream/1234567890123456789/extra',
      'https://www.xiaohongshu.com.evil.example/livestream/1234567890123456789',
      'https://www.flextv.co.kr/channels/123456',
      'https://www.flextv.co.kr/channels/123456/live/extra',
      'https://www.flextv.co.kr.evil.example/channels/123456/live',
    ];

    for (final url in urls) {
      expect(WebSearchRoomParser.parse(url), isNull, reason: url);
    }
  });

  test('AcFun shared room links resolve offline without treating author pages as streams', () async {
    expect(await LiveUrlTool.parseLiveUrl('看看这个直播 https://live.acfun.cn/live/42?source=share'), ['42', 'acfun']);
    expect(await LiveUrlTool.parseLiveUrl('https://live.acfun.cn/search?keyword=huya.com'), isEmpty);
  });





  test('GoodGame channel and player links resolve to durable channel or stream identities', () async {
    expect(await LiveUrlTool.parseLiveUrl('https://goodgame.ru/Verloin'), ['verloin', Sites.goodGameSite]);
    expect(await LiveUrlTool.parseLiveUrl('https://goodgame.ru/player?15365'), ['id:15365', Sites.goodGameSite]);
    expect(await LiveUrlTool.parseLiveUrl('https://live.fc2.com/10608314/'), ['10608314', Sites.fc2LiveSite]);
    expect(await LiveUrlTool.parseLiveUrl('https://goodgame.ru/streams'), isEmpty);
  });



  test('Taobao Live official room links resolve without a network request', () async {
    const url = 'https://h5.m.taobao.com/taolive/video.html?id=12345678901';
    expect(LiveUrlTool.containsSupportedLink('淘宝直播 $url'), isTrue);
    expect(await LiveUrlTool.parseLiveUrl('淘宝直播 $url'), ['live:12345678901', Sites.taobaoLiveSite]);
  });
}
