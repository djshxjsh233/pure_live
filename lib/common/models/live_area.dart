import 'dart:convert';

class LiveArea {
  String? platform = '';
  String? areaType = '';
  String? typeName = '';
  String? areaId = '';
  String? areaName = '';
  String? areaPic = '';
  String? shortName = '';

  /// Transient navigation metadata for platforms with a deeper taxonomy than
  /// the two-level parent/child shape.
  ///
  /// Douyin's game directory is three levels deep (游戏 > 竞技游戏 > 英雄联盟).
  /// A node keeps its own children so a drill-down page can offer the next
  /// level without re-fetching the catalogue. Deliberately excluded from
  /// [toJson]/[fromJson]: favourites and backups persist identity only, and a
  /// restored area can always re-derive its subtree from the live catalogue.
  List<LiveArea>? children;

  LiveArea({
    this.platform,
    this.areaType,
    this.typeName,
    this.areaId,
    this.areaName,
    this.areaPic,
    this.shortName,
    this.children,
  });

  LiveArea.fromJson(Map<String, dynamic> json)
    : platform = json['platform'] ?? '',
      areaType = json['areaType'] ?? '',
      typeName = json['typeName'] ?? '',
      areaId = json['areaId'] ?? '',
      areaName = json['areaName'] ?? '',
      areaPic = json['areaPic'] ?? '',
      shortName = json['shortName'] ?? '';

  /// Stable collection identity, not object equality: this model is mutable.
  String? get identityKey => identityKeyFor(platform: platform, areaId: areaId, areaType: areaType);

  bool hasSameIdentity(LiveArea other) {
    final key = identityKey;
    return key != null && key == other.identityKey;
  }

  /// Legacy sites identify categories by platform and ID, independently of
  /// the parent taxonomy.
  static String? identityKeyFor({String? platform, String? areaId, String? areaType}) {
    final site = platform?.trim().toLowerCase() ?? '';
    final id = areaId?.trim() ?? '';
    if (site.isEmpty || id.isEmpty) return null;
    return jsonEncode([site, '', id]);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'platform': platform,
    'areaType': areaType,
    'typeName': typeName,
    'areaId': areaId,
    'areaName': areaName,
    'areaPic': areaPic,
    'shortName': shortName,
  };
}
