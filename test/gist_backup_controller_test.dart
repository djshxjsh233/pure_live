import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/backup_controller.dart';
import 'package:pure_live/common/services/utils/hive_rx.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/gist_backup/gist_api.dart';
import 'package:pure_live/modules/gist_backup/gist_backup_controller.dart';

import 'support/fake_gist_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  late FakeGistApi api;
  late _FixtureBackupController backup;

  GistSnapshot snapshot(String stamp, {int size = 0}) => GistSnapshot(
    fileName: '${GistApi.filePrefix}$stamp${GistApi.fileSuffix}',
    savedAt: GistApi.parseTimestamp(stamp)!,
    size: size,
  );

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('gist-backup-controller-');
    Hive.init(hiveDirectory.path);
    await HivePrefUtil.init();
  });

  setUp(() async {
    Get.testMode = true;
    await HivePrefUtil.clear();
    api = FakeGistApi();
    backup = _FixtureBackupController();
    Get.put<BackupController>(backup);
  });

  tearDown(() async {
    Get.deleteAll(force: true);
    Get.reset();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  GistBackupController build({bool withToken = true, bool start = false}) {
    final controller = GistBackupController(apiFactory: (_) => api);
    if (withToken) controller.token.v = 'fake-token';
    // 只有需要验证「启动即刷新」的用例才走 GetX 生命周期，避免后台刷新
    // 与用例里显式的 refresh 争抢同一个 isBusy 门禁。
    if (start) Get.put<GistBackupController>(controller);
    return controller;
  }

  test('without a token nothing is configured and no snapshot is touched', () async {
    final controller = build(withToken: false);

    expect(controller.isConfigured, isFalse);
    expect(await controller.refreshSnapshots(), isFalse);
    expect(await controller.backupNow(), isFalse);
    expect(await controller.restore(), isFalse);
    expect(api.written, isEmpty);
    expect(api.ensureCalls, 0);
  });

  test('a rejected token is not persisted and reports the permission failure', () async {
    api.verifyFails = true;
    final controller = build(withToken: false);

    expect(await controller.saveToken('bad-token'), isFalse);
    expect(controller.isConfigured, isFalse);
    expect(controller.statusKey.v, 'gist_token_invalid');
    expect(controller.errorDetail.v, isNotEmpty);
  });

  test('an accepted token is stored and immediately resolves the latest snapshot', () async {
    api = FakeGistApi(
      initial: [snapshot('20260101_100000'), snapshot('20260201_100000')],
    );
    final controller = build(withToken: false);

    expect(await controller.saveToken(' good-token '), isTrue);
    expect(controller.token.v, 'good-token', reason: '令牌首尾空白必须裁剪');
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.snapshots.first.fileName,
      '${GistApi.filePrefix}20260201_100000${GistApi.fileSuffix}',
      reason: '快照按文件名（时间戳）倒序，第一份即最新',
    );
    expect(controller.gistId.v, 'gist-1');
    expect(HivePrefUtil.getString('gistToken'), 'good-token');
    expect(HivePrefUtil.getString('gistBackupId'), 'gist-1');
  });

  test('backup stamps a new snapshot and rotates the oldest file away', () async {
    api = FakeGistApi(
      initial: List<GistSnapshot>.generate(
        GistBackupController.maxSnapshots,
        (index) => snapshot('20260101_1000${index.toString().padLeft(2, '0')}'),
      ),
    );
    final controller = GistBackupController(
      apiFactory: (_) => api,
      now: () => DateTime(2026, 9, 28, 10, 30, 0),
    )..token.v = 'fake-token';
    await controller.refreshSnapshots();

    expect(await controller.backupNow(), isTrue);
    expect(api.written, ['${GistApi.filePrefix}20260928_103000${GistApi.fileSuffix}']);
    // 新增一份后总数 11，最旧的一份被同一次写入里删除。
    expect(api.removed, ['${GistApi.filePrefix}20260101_100000${GistApi.fileSuffix}']);
    expect(controller.snapshots, hasLength(GistBackupController.maxSnapshots));
    expect(controller.statusKey.v, 'gist_backup_ok');
  });

  test('backup uploads every settings section', () async {
    api = FakeGistApi();
    final controller = GistBackupController(
      apiFactory: (_) => api,
      now: () => DateTime(2026, 9, 28, 10, 30, 0),
    )..token.v = 'fake-token';

    expect(await controller.backupNow(), isTrue);
    expect(backup.exportCalls, 1);
    expect(backup.lastPayload.keys, containsAll(['app', 'theme', 'favorite', 'history', 'tags']));
  });

  test('backup never overwrites an existing snapshot with the same second', () async {
    api = FakeGistApi(initial: [snapshot('20260928_103000')]);
    final controller = GistBackupController(
      apiFactory: (_) => api,
      now: () => DateTime(2026, 9, 28, 10, 30, 0),
    )..token.v = 'fake-token';
    await controller.refreshSnapshots();

    expect(await controller.backupNow(), isTrue);
    expect(api.written.single, '${GistApi.filePrefix}20260928_103000-1${GistApi.fileSuffix}');
  });

  test('restore defaults to the newest snapshot and applies it through BackupController', () async {
    api = FakeGistApi(
      initial: [snapshot('20260101_100000'), snapshot('20260301_100000')],
      rawContent: jsonEncode({'backupVersion': BackupController.backupVersion, 'app': <String, dynamic>{}}),
    );
    final controller = build();
    await controller.refreshSnapshots();

    expect(await controller.restore(), isTrue);
    expect(api.readNames, ['${GistApi.filePrefix}20260301_100000${GistApi.fileSuffix}']);
    expect(backup.restoreCalls, 1);
    expect(controller.statusKey.v, 'gist_restore_ok');
  });

  test('restore can target an older snapshot by date', () async {
    final older = snapshot('20260101_100000');
    api = FakeGistApi(
      initial: [older, snapshot('20260301_100000')],
      rawContent: jsonEncode({'backupVersion': BackupController.backupVersion, 'app': <String, dynamic>{}}),
    );
    final controller = build();
    await controller.refreshSnapshots();

    expect(await controller.restore(older), isTrue);
    expect(api.readNames, [older.fileName]);
    expect(backup.restoreCalls, 1);
  });

  test('a malformed cloud payload fails without touching local settings', () async {
    api = FakeGistApi(initial: [snapshot('20260101_100000')], rawContent: '"nope"');
    final controller = build();
    await controller.refreshSnapshots();

    expect(await controller.restore(), isFalse);
    expect(backup.restoreCalls, 0);
    expect(controller.statusKey.v, 'gist_restore_failed');
  });

  test('a lost gist id is recovered from the account instead of failing', () async {
    await HivePrefUtil.setString('gistBackupId', 'stale-id');
    api = FakeGistApi(initial: [snapshot('20260101_100000')], gistId: 'recovered-id');
    final controller = build(start: true);
    for (var i = 0; i < 40 && controller.gistId.v != 'recovered-id'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(controller.gistId.v, 'recovered-id');
    expect(controller.snapshots, hasLength(1));
    expect(HivePrefUtil.getString('gistBackupId'), 'recovered-id');
  });

  test('deleting a snapshot drops it from the cached list', () async {
    api = FakeGistApi(initial: [snapshot('20260101_100000'), snapshot('20260201_100000')]);
    final controller = build();
    await controller.refreshSnapshots();
    expect(controller.snapshots, hasLength(2));

    expect(await controller.deleteSnapshot(controller.snapshots.first), isTrue);
    expect(api.removed, ['${GistApi.filePrefix}20260201_100000${GistApi.fileSuffix}']);
    expect(controller.snapshots.map((item) => item.fileName), ['${GistApi.filePrefix}20260101_100000${GistApi.fileSuffix}']);
  });

  test('clearing the token drops the cached cloud identity', () async {
    api = FakeGistApi(initial: [snapshot('20260101_100000')]);
    final controller = build();
    await controller.refreshSnapshots();
    expect(controller.gistId.v, 'gist-1');

    await controller.clearToken();
    expect(controller.token.v, isEmpty);
    expect(controller.gistId.v, isEmpty);
    expect(controller.snapshots, isEmpty);
    expect(HivePrefUtil.getString('gistToken') ?? '', isEmpty);
  });
}

class _FixtureBackupController extends BackupController {
  int restoreCalls = 0;
  int exportCalls = 0;
  Map<String, dynamic> lastPayload = const {};

  @override
  // The controller under test only needs export/restore; nothing runs on init.
  // ignore: must_call_super
  void onInit() {}

  @override
  Map<String, dynamic> exportAllSettings({bool includeSensitiveData = true}) {
    exportCalls++;
    lastPayload = {
      'backupVersion': BackupController.backupVersion,
      'app': <String, dynamic>{},
      'theme': <String, dynamic>{},
      'favorite': <String, dynamic>{},
      'history': <String, dynamic>{},
      'tags': <String, dynamic>{},
    };
    return lastPayload;
  }

  @override
  Future<void> restoreAllSettings(Map<String, dynamic> data) async {
    restoreCalls++;
  }
}
