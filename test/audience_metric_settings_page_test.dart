import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/app_settings_controller.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/settings/pages/audience_metric_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  late Map<String, dynamic> english;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-audience-settings-test-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    english = jsonDecode(await File('assets/translations/en.json').readAsString()) as Map<String, dynamic>;
    Hive.init(hiveDirectory.path);
    await HivePrefUtil.init();
  });

  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    Get.put<SettingsService>(_TestSettingsService(_AudienceTestAppSettings()));
  });

  tearDown(Get.reset);

  tearDownAll(() async {
    await Hive.close().timeout(const Duration(seconds: 10));
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('unsupported audience rows render without an empty GetX card', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('zh')],
        path: 'assets/translations',
        fallbackLocale: const Locale('zh'),
        assetLoader: const _AudienceAssetLoader(),
        child: Builder(
          builder: (context) => GetMaterialApp(
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            home: const AudienceMetricSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('audience-platform-bilibili')), findsOneWidget);
    expect(find.text('哔哩哔哩'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('audience-platform-douyin')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final kuaishou = find.byKey(const ValueKey('audience-platform-kuaishou'));
    await tester.ensureVisible(kuaishou);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(kuaishou).value, isTrue);
    await tester.tap(kuaishou);
    await tester.pumpAndSettle();
    expect(SettingsService.to.app.isRealOnlineEnabledFor('kuaishou'), isFalse);
    expect(tester.widget<SwitchListTile>(kuaishou).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy platform spellings render through canonical switch state', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = SettingsService.to.app;
    app.realOnlinePlatforms.assignAll([' DOUYIN ', 'HUYA']);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('zh')],
        path: 'assets/translations',
        fallbackLocale: const Locale('zh'),
        assetLoader: const _AudienceAssetLoader(),
        child: Builder(
          builder: (context) => GetMaterialApp(
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            home: const AudienceMetricSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final douyin = find.byKey(const ValueKey('audience-platform-douyin'));
    await tester.ensureVisible(douyin);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(douyin).value, isTrue);
    expect(app.realOnlinePlatforms, [' DOUYIN ', 'HUYA']);
    expect(app.toJson()['realOnlinePlatforms'], ['douyin']);

    await tester.tap(douyin);
    await tester.pumpAndSettle();
    expect(app.realOnlinePlatforms, isEmpty);
    expect(tester.widget<SwitchListTile>(douyin).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every live platform stays localized and operable in narrow very-large text', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        startLocale: const Locale('en'),
        fallbackLocale: const Locale('en'),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: _Translations(english),
        child: Builder(
          builder: (context) => GetMaterialApp(
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(3)),
              child: child!,
            ),
            home: const AudienceMetricSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final onlineMode = find.byKey(const ValueKey('audience-mode-online'));
    await _scrollPageUntilHitTestable(tester, onlineMode);
    await tester.tap(onlineMode.hitTestable());
    await tester.pumpAndSettle();
    expect(SettingsService.to.app.preferRealOnlineCounts.value, isTrue);

    const expectedPlatforms = <String, String>{
      'bilibili': 'Bilibili',
      'douyu': 'Douyu',
      'huya': 'Huya',
      'douyin': 'Douyin',
      'kuaishou': 'Kuaishou',
    };
    for (final entry in expectedPlatforms.entries) {
      final tile = find.byKey(ValueKey('audience-platform-${entry.key}'));
      await _scrollPageUntilHitTestable(tester, tile);
      expect(find.descendant(of: tile, matching: find.text(entry.value)), findsOneWidget);
      final detail = find.byKey(ValueKey('audience-platform-detail-${entry.key}'));
      expect(tester.getRect(detail).bottom, lessThanOrEqualTo(tester.getRect(tile).bottom));
      expect(tester.takeException(), isNull);
    }
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
}

Future<void> _scrollPageUntilHitTestable(WidgetTester tester, Finder target) async {
  final scrollable = tester.state<ScrollableState>(
    find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first,
  );
  for (var attempt = 0; attempt < 120; attempt++) {
    if (target.hitTestable().evaluate().isNotEmpty) return;
    final position = scrollable.position;
    final delta = position.viewportDimension * 0.25;
    final next = (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent);
    position.jumpTo(next);
    await tester.pump();
  }
  fail('Target did not become hit-testable after bounded page scrolling.');
}

class _AudienceAssetLoader extends AssetLoader {
  const _AudienceAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {
    'audience_metric_settings': '观看数据与排行口径',
    'audience_display_mode': '显示方式',
    'audience_mode_heat': '平台热度优先',
    'audience_mode_heat_desc': '按平台原始口径显示',
    'audience_mode_online': '真实在线人数优先',
    'audience_mode_online_desc': '支持的平台显示并发在线',
    'audience_ranking_rule_desc': '在线优先，其次等待数据，最后是热度。',
    'audience_online_platforms': '真实在线平台开关',
    'audience_source_room_list': '房间列表直接提供',
    'audience_source_room_realtime': '进入房间后实时提供',
    'audience_source_not_exposed': '平台公开接口仅提供热度',
    'site_bilibili': '哔哩哔哩',
    'site_douyu': '斗鱼',
    'site_huya': '虎牙',
    'site_douyin': '抖音',
    'site_kuaishou': '快手',
    'site_openrec': 'mellow-fan (OPENREC)',
    'site_ttinglive': 'FLEX TV (TTingLive)',
    'site_xiaohongshu': '小红书',
    'audience_bilibili_detail': '热度与累计观看分开显示',
    'audience_douyu_detail': '公开字段按热度显示',
    'audience_huya_detail': '公开字段按热度显示',
    'audience_douyin_detail': '列表可提供在线值',
    'audience_kuaishou_detail': '列表可提供在线值',
    'audience_openrec_detail': '公开在线人数与累计值分开，隐藏时保持未知',
    'audience_ttinglive_detail': '目录提供当前观看数，频道详情不提供',
    'audience_xiaohongshu_detail': '展示文本不作为并发人数',
    'audience_metric_fallback_desc': '各平台字段口径会单独标注。',
  };
}

class _Translations extends AssetLoader {
  const _Translations(this.values);

  final Map<String, dynamic> values;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}

// Widget tests own a fake clock. Keep their observable state in memory; the
// actual Hive write/upgrade contract is covered by the settings persistence tests.
class _AudienceTestAppSettings extends AppSettingsController {
  final RxList<String> _onlinePlatforms = List<String>.from(AppSettingsController.defaultRealOnlinePlatforms).obs;
  @override
  RxList<String> get realOnlinePlatforms => _onlinePlatforms;
}

class _TestSettingsService extends SettingsService {
  _TestSettingsService(this._app) : _font = FontSettingsController();

  final AppSettingsController _app;
  final FontSettingsController _font;

  @override
  AppSettingsController get app => _app;

  @override
  FontSettingsController get font => _font;

  @override
  // Test fixture intentionally skips production controller registrations.
  // ignore: must_call_super
  void onInit() {}
}
