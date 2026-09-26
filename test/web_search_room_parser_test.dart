import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/modules/search/web_search_room_parser.dart';
import 'package:pure_live/common/utils/live_url_tool.dart';

void main() {

  test('ignores search/navigation pages and lookalike domains', () {
    const urls = [
      'https://www.huya.com/search?hsk=test',
      'https://www.douyu.com/topic/something',
      'https://live.kuaishou.com/search?keyword=test',
      'https://live.bilibili.com/p/eden/area-tags',
      'https://www.huya.com.evil.example/1234',
      'javascript:alert(1)',
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
