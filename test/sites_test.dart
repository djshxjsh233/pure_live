import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/core/interface/live_site.dart';

void main() {
  test('every registered platform has a user-visible label in both bundled locales', () async {
    for (final locale in ['zh', 'en']) {
      final labels = jsonDecode(await File('assets/translations/$locale.json').readAsString()) as Map;
      for (final id in {Sites.allSite, ...Sites.supportedSiteIds}) {
        final label = labels['site_$id'];
        expect(label, isA<String>(), reason: '$locale site_$id');
        expect((label as String).trim(), isNotEmpty);
        expect(label, isNot('site_$id'));
      }
      expect(labels['site_openrec'], 'mellow-fan (OPENREC)');
      expect(labels['site_ttinglive'], 'FLEX TV (TTingLive)');
      expect(labels['site_xiaohongshu'], isNotEmpty);
      expect(labels['recorder_input_integrity_failed'], isA<String>());
    }
  });
  test('validates live-room route platform ids without constructing a site', () {
    expect(Sites.isSupported('bilibili'), isTrue);
    expect(Sites.isSupported(' HUYA '), isTrue);
    expect(Sites.isSupported(' Douyu '), isTrue);
    expect(Sites.isSupported(' Kuaishou '), isTrue);
    expect(Sites.isSupported('unknown-platform'), isFalse);
  });

  test('resolves imported platform ids after trimming and case normalization', () {
    expect(Sites.of(' BILIBILI ').id, Sites.bilibiliSite);
    expect(Sites.of(' HuYa ').id, Sites.huyaSite);
  });

  test('failure-prone adapters expose a refresh path that preserves unknown state on transport errors', () {
    for (final siteId in [Sites.bilibiliSite, Sites.douyuSite, Sites.kuaishouSite]) {
      expect(Sites.of(siteId).liveSite, isA<LiveSiteRoomRefresher>(), reason: siteId);
    }
  });
}
