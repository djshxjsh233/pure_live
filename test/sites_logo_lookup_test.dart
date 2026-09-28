import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/sites.dart';

void main() {
  test('lightweight logo lookup preserves registered artwork without creating adapters', () {
    expect(Sites.logoForId(' BILIBILI '), 'assets/images/bilibili_2.png');
    // Artwork lookup normalizes case and whitespace without building an adapter.
    expect(Sites.logoForId(' KUAISHOU '), 'assets/images/kuaishou.png');
    for (final id in Sites.supportedSiteIds) {
      final asset = Sites.logoForId(id);
      expect(asset, Sites.of(id).logo, reason: id);
      expect(File(asset).existsSync(), isTrue, reason: id);
    }
    expect(() => Sites.logoForId('unregistered'), throwsStateError);
  });
}
