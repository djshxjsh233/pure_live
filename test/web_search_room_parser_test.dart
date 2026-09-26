import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/search/web_search_room_parser.dart';

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
}
