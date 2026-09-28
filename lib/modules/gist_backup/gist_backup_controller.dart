import 'dart:async';
import 'dart:convert';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/common/services/settings/backup_controller.dart';
import 'package:pure_live/modules/gist_backup/gist_api.dart';

/// GitHub Gist 云备份控制器。
///
/// 所有快照都放在一个私有 Gist 里，每份备份是一个带时间戳的文件；
/// 只在本机保存令牌与 gist id，快照本体全部留在 GitHub。
class GistBackupController extends GetxController {
  GistBackupController({
    GistApi Function(String token)? apiFactory,
    DateTime Function()? now,
    this.autoRefresh = true,
  }) : _apiFactory = apiFactory ?? _defaultApiFactory,
       _now = now ?? DateTime.now;

  static GistBackupController get to => Get.find();

  /// 云端保留的快照份数，超出后从最旧的开始滚动删除。
  static const int maxSnapshots = 10;

  static GistApi _defaultApiFactory(String token) => GistApi(token: token);

  final GistApi Function(String token) _apiFactory;
  final DateTime Function() _now;

  /// 页面打开时是否立刻拉取快照；测试里关掉以避免与断言争抢。
  final bool autoRefresh;

  final RxString token = hiveString('gistToken', '');
  final RxString gistId = hiveString('gistBackupId', '');
  final RxString lastBackupAt = hiveString('gistBackupAt', '');
  final RxList<GistSnapshot> snapshots = <GistSnapshot>[].obs;
  final RxBool isChecking = false.obs;
  final RxBool isBusy = false.obs;
  final RxBool isLoaded = false.obs;
  final RxString statusKey = ''.obs;
  final RxString errorDetail = ''.obs;

  bool get isConfigured => token.v.trim().isNotEmpty;

  GistApi? _api() {
    final value = token.v.trim();
    if (value.isEmpty) return null;
    return _apiFactory(value);
  }

  @override
  void onInit() {
    super.onInit();
    if (autoRefresh && isConfigured) unawaited(refreshSnapshots(silent: true));
  }

  Future<bool> saveToken(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    isChecking.value = true;
    errorDetail.value = '';
    statusKey.value = 'gist_token_checking';
    try {
      final api = _apiFactory(trimmed);
      await api.verifyToken();
      token.v = trimmed;
      // 令牌换了就必须重新定位备份 Gist，旧 id 可能不属于新账号。
      gistId.v = '';
      isLoaded.value = false;
      snapshots.clear();
      statusKey.value = 'gist_token_invalid_ok';
      HivePrefUtil.setString('gistToken', trimmed);
      unawaited(refreshSnapshots(silent: true));
      return true;
    } catch (error) {
      errorDetail.value = _describe(error);
      statusKey.value = 'gist_token_invalid';
      return false;
    } finally {
      isChecking.value = false;
    }
  }

  Future<void> clearToken() async {
    token.v = '';
    gistId.v = '';
    lastBackupAt.v = '';
    snapshots.clear();
    isLoaded.value = false;
    statusKey.value = '';
    errorDetail.value = '';
    // Rx 监听器异步回写 Hive，先让这些写入落地再删 key，避免被后到的空值覆盖。
    await Future<void>.delayed(Duration.zero);
    await HivePrefUtil.remove('gistToken');
    await HivePrefUtil.remove('gistBackupId');
    await HivePrefUtil.remove('gistBackupAt');
  }

  /// 定位（必要时创建）备份 Gist 并刷新快照列表。
  Future<bool> refreshSnapshots({bool silent = false}) async {
    final api = _api();
    if (api == null || isBusy.value) return false;
    if (!silent) statusKey.value = 'gist_loading';
    isBusy.value = true;
    errorDetail.value = '';
    try {
      final id = await _ensureGist(api);
      final list = await api.listSnapshots(id);
      _applyList(id, list);
      if (!silent) statusKey.value = list.isEmpty ? 'gist_no_snapshot' : 'gist_load_ok';
      return true;
    } catch (error) {
      errorDetail.value = _describe(error);
      statusKey.value = 'gist_load_failed';
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  Future<String> _ensureGist(GistApi api) async {
    final known = gistId.v.trim();
    if (known.isNotEmpty) {
      try {
        await api.listSnapshots(known);
        return known;
      } on GistApiException catch (error) {
        // 只有确认不存在才重新找回/创建，其它错误（网络、权限）照实抛出。
        if (error.statusCode != 404) rethrow;
      }
    }
    final found = await api.ensureBackupGist();
    gistId.v = found;
    HivePrefUtil.setString('gistBackupId', found);
    return found;
  }

  void _applyList(String id, List<GistSnapshot> list) {
    snapshots.assignAll(list);
    isLoaded.value = true;
    gistId.v = id;
    HivePrefUtil.setString('gistBackupId', id);
    if (list.isNotEmpty) {
      lastBackupAt.v = list.first.displayTime;
      HivePrefUtil.setString('gistBackupAt', list.first.displayTime);
    }
  }

  /// 备份：写入一份带时间戳的新快照，并滚动删除最旧的。
  Future<bool> backupNow() async {
    final api = _api();
    if (api == null || isBusy.value) return false;
    isBusy.value = true;
    errorDetail.value = '';
    statusKey.value = 'gist_backing_up';
    try {
      final id = await _ensureGist(api);
      final existing = await api.listSnapshots(id);
      final fileName = GistApi.snapshotFileName(
        _now(),
        existing.map((item) => item.fileName).toSet(),
      );
      final content = jsonEncode(Get.find<BackupController>().exportAllSettings());
      // 写入与滚动清理放在同一个 PATCH：任一步失败都不会留下半截状态。
      final remove = existing.length >= maxSnapshots
          ? existing.sublist(maxSnapshots - 1).map((item) => item.fileName).toList(growable: false)
          : const <String>[];
      await api.writeSnapshot(id, fileName: fileName, content: content, removeFileNames: remove);
      _applyList(id, await api.listSnapshots(id));
      statusKey.value = 'gist_backup_ok';
      return true;
    } catch (error) {
      errorDetail.value = _describe(error);
      statusKey.value = 'gist_backup_failed';
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  /// 恢复指定快照；[snapshot] 为空时使用最新一份。
  Future<bool> restore([GistSnapshot? snapshot]) async {
    final api = _api();
    if (api == null || isBusy.value) return false;
    if (snapshots.isEmpty) {
      statusKey.value = 'gist_no_snapshot';
      return false;
    }
    final target = snapshot ?? snapshots.first;
    isBusy.value = true;
    errorDetail.value = '';
    statusKey.value = 'gist_restoring';
    try {
      final id = await _ensureGist(api);
      final raw = await api.readSnapshot(id, target.fileName);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('backup payload is not an object');
      await Get.find<BackupController>().restoreAllSettings(Map<String, dynamic>.from(decoded));
      statusKey.value = 'gist_restore_ok';
      return true;
    } catch (error) {
      errorDetail.value = _describe(error);
      statusKey.value = 'gist_restore_failed';
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  Future<bool> deleteSnapshot(GistSnapshot snapshot) async {
    final api = _api();
    if (api == null || isBusy.value) return false;
    isBusy.value = true;
    errorDetail.value = '';
    try {
      final id = await _ensureGist(api);
      await api.deleteSnapshot(id, snapshot.fileName);
      snapshots.removeWhere((item) => item.fileName == snapshot.fileName);
      statusKey.value = 'gist_delete_ok';
      return true;
    } catch (error) {
      errorDetail.value = _describe(error);
      statusKey.value = 'gist_delete_failed';
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  static String _describe(Object error) {
    if (error is GistApiException) {
      if (error.isUnauthorized) return i18n('gist_error_token');
      if (error.statusCode == 404) return i18n('gist_error_not_found');
      if (error.statusCode == 0) return i18n('gist_error_network');
      return i18n('gist_error_status', args: {'code': '${error.statusCode}'});
    }
    return '$error';
  }
}
