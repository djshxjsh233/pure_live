import 'package:pure_live/core/sites.dart';

enum NativeSearchCoverage {
  liveOnly,
  liveAndOffline,
  channelLookup,
  roomLookup,
  showcaseSnapshot,
  webOnly,
  unavailable,
}

class LiveSearchCapability {
  const LiveSearchCapability({required this.coverage, required this.supportsPagination, this.supportsWebSearch = true});

  final NativeSearchCoverage coverage;
  final bool supportsPagination;
  final bool supportsWebSearch;

  bool get supportsNativeSearch =>
      coverage != NativeSearchCoverage.webOnly && coverage != NativeSearchCoverage.unavailable;
  bool get mayIncludeOffline =>
      coverage == NativeSearchCoverage.liveAndOffline ||
      coverage == NativeSearchCoverage.channelLookup ||
      coverage == NativeSearchCoverage.roomLookup;
}

class LiveSearchCapabilities {
  const LiveSearchCapabilities._();

  static const Map<String, LiveSearchCapability> _byPlatform = {
    // These registered adapters already implement native search. Keep their
    // UI capability in sync with the actual exact-ID, snapshot or paged API.
    Sites.bilibiliSite: LiveSearchCapability(coverage: NativeSearchCoverage.liveAndOffline, supportsPagination: true),
    Sites.douyuSite: LiveSearchCapability(coverage: NativeSearchCoverage.liveAndOffline, supportsPagination: true),
    Sites.huyaSite: LiveSearchCapability(coverage: NativeSearchCoverage.liveOnly, supportsPagination: true),
    Sites.douyinSite: LiveSearchCapability(coverage: NativeSearchCoverage.liveOnly, supportsPagination: true),
    Sites.kuaishouSite: LiveSearchCapability(coverage: NativeSearchCoverage.webOnly, supportsPagination: false),
  };

  static const LiveSearchCapability _unknown = LiveSearchCapability(
    coverage: NativeSearchCoverage.webOnly,
    supportsPagination: false,
  );

  static LiveSearchCapability forPlatform(String id) => _byPlatform[id.toLowerCase()] ?? _unknown;
}
