import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/routes/app_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records which partition each level actually requested, so a page that shows
/// the wrong level's rooms cannot pass by rendering the right title.
class _Site extends LiveSite {
  final requested = <String>[];

  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea area, {int page = 1, int pageSize = 30}) async {
    requested.add(area.areaId ?? '');
    return [
      LiveRoom(
        roomId: 'room-${area.areaId}',
        title: 'room-${area.areaName}',
        nick: 'nick',
        platform: Sites.douyinSite,
        liveStatus: LiveStatus.live,
        status: true,
      ),
    ];
  }
}

class _Translations extends AssetLoader {
  const _Translations(this.translations);

  final Map<String, dynamic> translations;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => translations;
}

LiveArea _leaf() =>
    LiveArea(platform: 'douyin', areaId: '1010014,1', areaName: '英雄联盟', typeName: '竞技游戏', areaType: '2,1');

LiveArea _competitive() => LiveArea(
  platform: 'douyin',
  areaId: '2,1',
  areaName: '竞技游戏',
  typeName: '游戏',
  areaType: '103,4',
  children: [_leaf()],
);

LiveArea _game() => LiveArea(
  platform: 'douyin',
  areaId: '103,4',
  areaName: '游戏',
  typeName: '游戏',
  areaType: '103,4',
  children: [_competitive()],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> translations;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    translations = jsonDecode(await File('assets/translations/en.json').readAsString()) as Map<String, dynamic>;
    await Hive.openBox<dynamic>('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
  });

  setUp(() {
    Get.testMode = true;
    Get.reset();
    Get.put(SettingsService(), permanent: true);
  });

  tearDown(Get.reset);
  tearDownAll(Hive.close);

  testWidgets('game directory drills down one level per push and walks back the same way', (tester) async {
    final source = _Site();
    final site = Site(id: Sites.douyinSite, name: '抖音', logo: '', liveSite: source);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        startLocale: const Locale('en'),
        fallbackLocale: const Locale('en'),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: _Translations(translations),
        child: Builder(
          builder: (context) => GetMaterialApp(
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            initialRoute: '/',
            getPages: [
              GetPage(
                name: '/',
                page: () => const Scaffold(key: ValueKey('root'), body: SizedBox.shrink()),
              ),
              ...AppPages.routes.where((page) => page.name == RoutePath.kAreaRooms),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    AppNavigator.toCategoryDetail(site: site, category: _game());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '游戏'), findsOneWidget);
    expect(find.byKey(const ValueKey('area-sub-category-strip')), findsOneWidget);
    expect(find.text('竞技游戏'), findsOneWidget);
    expect(find.text('room-游戏'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('area-sub-category-0')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '竞技游戏'), findsOneWidget);
    expect(find.text('英雄联盟'), findsOneWidget);
    expect(find.text('room-竞技游戏'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('area-sub-category-0')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '英雄联盟'), findsOneWidget);
    expect(find.byKey(const ValueKey('area-sub-category-strip')), findsNothing);
    expect(find.text('room-英雄联盟'), findsOneWidget);

    // Every level requested its own partition, in drill-down order. Repeated
    // reads of one partition are the pager's existing refresh behaviour, so
    // only the first sighting of each level is asserted.
    final firstSeen = <String>[];
    for (final id in source.requested) {
      if (!firstSeen.contains(id)) firstSeen.add(id);
    }
    expect(firstSeen, ['103,4', '2,1', '1010014,1']);

    // Pages stacked: back walks up the directory instead of leaving it.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '竞技游戏'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '游戏'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('root')), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
