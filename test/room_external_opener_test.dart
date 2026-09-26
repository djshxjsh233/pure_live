import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/danmaku/douyin_danmaku.dart';
import 'package:pure_live/core/danmaku/huya_danmaku.dart';
import 'package:pure_live/modules/live_play/services/room_external_opener.dart';

void main() {
  final newPlatformWebTargets = <String, (String, String)>{
    'goodgame': ('fixture_channel', 'https://goodgame.ru/fixture_channel'),
    'fc2live': ('12345', 'https://live.fc2.com/12345/'),
    'taobaolive': ('live:12345', 'https://h5.m.taobao.com/taolive/video.html?id=12345'),
    'looklive': ('12345', 'https://look.163.com/live?id=12345'),
  };
  for (final entry in newPlatformWebTargets.entries) {
    test('${entry.key} opens its verified official room URL', () async {
      final room = LiveRoom(platform: entry.key, roomId: entry.value.$1, link: 'https://untrusted.example/room');
      final target = RoomExternalOpener.resolve(entry.key, room);
      expect(target?.web, entry.value.$2);
      expect(target?.native, isNull);
      final launches = <String>[];
      expect(
        await RoomExternalOpener.open(
          site: entry.key,
          room: room,
          android: false,
          launch: (url) async {
            launches.add(url);
            return true;
          },
        ),
        RoomExternalOpenResult.opened,
      );
      expect(launches, [entry.value.$2]);
    });
  }
  test('GoodGame player identity retains its player URL', () {
    expect(
      RoomExternalOpener.resolve('goodgame', LiveRoom(roomId: 'id:12345'))?.web,
      'https://goodgame.ru/player?src=12345',
    );
  });
  test('new platform malformed identities never become shell targets', () {
    final invalid = <String, String>{
      'goodgame': 'id:0',
      'fc2live': 'abc',
      'taobaolive': 'live:0',
      'looklive': '1',
    };
    for (final entry in invalid.entries) {
      expect(RoomExternalOpener.resolve(entry.key, LiveRoom(roomId: entry.value)), isNull, reason: entry.key);
    }
  });
  final webTargets = {
    'bilibili': 'https://live.bilibili.com/12345',
    'douyin': 'https://live.douyin.com/12345',
    'huya': 'https://www.huya.com/12345',
    'douyu': 'https://www.douyu.com/12345',
    'kuaishou': 'https://live.kuaishou.com/u/12345',
  };

  for (final entry in webTargets.entries) {
    test('${entry.key} desktop opens the expected web target exactly once', () async {
      final calls = <String>[];
      final result = await RoomExternalOpener.open(
        site: entry.key,
        room: LiveRoom(roomId: '12345', platform: entry.key),
        android: false,
        launch: (url) async {
          calls.add(url);
          return true;
        },
      );
      expect(result, RoomExternalOpenResult.opened);
      expect(calls, [entry.value]);
    });
  }

  test('Douyin Android uses the same official page, without an invented deep link', () async {
    final calls = <String>[];
    expect(
      await RoomExternalOpener.open(
        site: 'douyin',
        room: LiveRoom(roomId: '12345'),
        android: true,
        launch: (url) async {
          calls.add(url);
          return true;
        },
      ),
      RoomExternalOpenResult.opened,
    );
    expect(calls, [webTargets['douyin']]);
  });

  for (final throws in [false, true]) {
    test('Android native ${throws ? 'exception' : 'false'} falls back once', () async {
      final calls = <String>[];
      var notices = 0;
      final result = await RoomExternalOpener.open(
        site: 'bilibili',
        room: LiveRoom(roomId: '12345'),
        android: true,
        onBrowserFallback: () => notices++,
        launch: (url) async {
          calls.add(url);
          if (calls.length == 1) {
            if (throws) throw StateError('fixture');
            return false;
          }
          return true;
        },
      );
      expect(result, RoomExternalOpenResult.opened);
      expect(calls, ['bilibili://live/12345', webTargets['bilibili']]);
      expect(notices, 1);
    });
  }

  test('native success does not open a browser', () async {
    final calls = <String>[];
    expect(
      await RoomExternalOpener.open(
        site: 'bilibili',
        room: LiveRoom(roomId: '12345'),
        android: true,
        onBrowserFallback: () => fail('unneeded fallback'),
        launch: (url) async {
          calls.add(url);
          return true;
        },
      ),
      RoomExternalOpenResult.opened,
    );
    expect(calls, ['bilibili://live/12345']);
  });

  test('both failures produce a failed result, never an unhandled second exception', () async {
    var calls = 0;
    expect(
      await RoomExternalOpener.open(
        site: 'bilibili',
        room: LiveRoom(roomId: '12345'),
        android: true,
        launch: (_) async {
          calls++;
          throw StateError('fixture');
        },
      ),
      RoomExternalOpenResult.failed,
    );
    expect(calls, 2);
  });

  for (final android in [false, true]) {
    test('web-only failure on android=$android is not retried', () async {
      var calls = 0;
      expect(
        await RoomExternalOpener.open(
          site: 'douyin',
          room: LiveRoom(roomId: '12345'),
          android: android,
          onBrowserFallback: () => fail('same web target is not a native fallback'),
          launch: (_) async {
            calls++;
            return false;
          },
        ),
        RoomExternalOpenResult.failed,
      );
      expect(calls, 1);
    });
  }

  test('exit during a native attempt suppresses stale fallback and notifications', () async {
    final pending = Completer<bool>();
    var current = true;
    var calls = 0;
    final action = RoomExternalOpener.open(
      site: 'bilibili',
      room: LiveRoom(roomId: '12345'),
      android: true,
      isCurrent: () => current,
      onBrowserFallback: () => fail('owner is stale'),
      launch: (_) {
        calls++;
        return pending.future;
      },
    );
    current = false;
    pending.complete(false);
    expect(await action, RoomExternalOpenResult.cancelled);
    expect(calls, 1);
  });

  test('an already stale owner sends no OS request', () async {
    expect(
      await RoomExternalOpener.open(
        site: 'douyin',
        room: LiveRoom(roomId: '12345'),
        android: true,
        isCurrent: () => false,
        launch: (_) async => fail('stale action'),
      ),
      RoomExternalOpenResult.cancelled,
    );
  });

  test('a stale browser completion is not reported as success/failure for a new room', () async {
    var current = true;
    expect(
      await RoomExternalOpener.open(
        site: 'douyin',
        room: LiveRoom(roomId: '12345'),
        android: false,
        isCurrent: () => current,
        launch: (_) async {
          current = false;
          return true;
        },
      ),
      RoomExternalOpenResult.cancelled,
    );
  });

  test('unknown site and IPTV ignore imported URLs', () async {
    for (final site in ['unknown', 'iptv']) {
      expect(
        await RoomExternalOpener.open(
          site: site,
          room: LiveRoom(roomId: '12345', link: 'file:///C:/Windows/System32'),
          android: false,
          launch: (_) async => fail('not an official room URL'),
        ),
        RoomExternalOpenResult.unavailable,
      );
    }
  });

  test('invalid identities never become shell or guessed room targets', () {
    for (final id in <String?>[null, '', ' ', '.', '..', '../1', '1/2', '1?x=y', '1#x', '1%2f2', '1\n2', '1\\2']) {
      for (final site in ['douyu', 'huya', 'bilibili']) {
        expect(RoomExternalOpener.resolve(site, LiveRoom(roomId: id)), isNull, reason: '$site/$id');
      }
    }
  });

  test('Douyin uses separate canonical web and native IDs without copying cookies', () {
    final args = DouyinDanmakuArgs(webRid: '2468', roomId: '98765', userId: '44', cookie: 'private-fixture');
    final target = RoomExternalOpener.resolve('douyin', LiveRoom(roomId: '12345', danmakuData: args))!;
    expect(target.web, 'https://live.douyin.com/2468');
    expect(target.native, 'snssdk1128://webcast_room?room_id=98765');
    expect('${target.web}${target.native}', isNot(contains(args.cookie)));
  });

  test('missing or wrong optional deep-link metadata keeps independent webpage targets', () {
    for (final data in [
      null,
      {'old': 'fixture'},
    ]) {
      for (final site in ['douyin', 'huya']) {
        final target = RoomExternalOpener.resolve(site, LiveRoom(roomId: '12345', danmakuData: data))!;
        expect(target.web, webTargets[site]);
        expect(target.native, isNull);
      }
    }
    expect(RoomExternalOpener.resolve('kuaishou', LiveRoom(roomId: '12345'))!.native, isNull);
  });

  test('existing Huya deep-link contract stays available with its metadata', () {
    final huya = RoomExternalOpener.resolve(
      'huya',
      LiveRoom(roomId: '12345', danmakuData: HuyaDanmakuArgs(uid: 11, topSid: 22, subSid: 33)),
    )!;
    expect(huya.native, startsWith('yykiwi://homepage/index.html?'));
    expect(huya.native, contains('subid%3D33'));
  });

  test('Kuaishou stream value stays in a single query field', () {
    final target = RoomExternalOpener.resolve('kuaishou', LiveRoom(roomId: '12345', link: 'stream&path=bad'))!;
    final query = Uri.parse(target.native!).queryParameters;
    expect(query['liveStreamId'], 'stream&path=bad');
    expect(query['path'], '/rest/n/live/feed/sharePage/slide/more');
  });
}
