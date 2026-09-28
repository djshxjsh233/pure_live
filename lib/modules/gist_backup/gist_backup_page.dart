import 'dart:async';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/gist_backup/gist_api.dart';
import 'package:pure_live/modules/gist_backup/gist_backup_controller.dart';
import 'package:remixicon/remixicon.dart';

/// GitHub Gist 云备份页。
///
/// 只保留三件事：配置令牌、备份/恢复、按日期挑选快照。
class GistBackupPage extends StatelessWidget {
  const GistBackupPage({super.key});

  GistBackupController get controller => Get.find<GistBackupController>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n('gist_cloud_backup'))),
      body: Obx(() {
        final statusKey = controller.statusKey.value;
        return ListView(
          physics: const PureLiveScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            context.buildGroupTitle(i18n('gist_account')),
            context.buildModernCard([
              context.buildTile(
                iconWidget: controller.isChecking.value
                    ? RotationTransition(
                        turns: const AlwaysStoppedAnimation(0.5),
                        child: Icon(Remix.refresh_line, color: Theme.of(context).colorScheme.primary, size: 22),
                      )
                    : Icon(
                        Remix.key_2_line,
                        color: controller.isConfigured ? null : Theme.of(context).colorScheme.error,
                        size: 22,
                      ),
                title: controller.isConfigured ? i18n('gist_token_set') : i18n('gist_token_not_set'),
                subtitle: controller.isConfigured ? i18n('gist_token_set_desc') : i18n('gist_token_not_set_desc'),
                subtitleColor: controller.isConfigured
                    ? null
                    : Theme.of(context).colorScheme.error.withValues(alpha: 0.8),
                isLong: true,
                onTap: controller.isChecking.value ? null : () => unawaited(_showTokenDialog(context)),
              ),
              if (controller.isConfigured)
                context.buildTile(
                  icon: Remix.delete_bin_line,
                  title: i18n('gist_clear_token'),
                  isLong: true,
                  iconColor: Theme.of(context).colorScheme.error,
                  onTap: controller.isBusy.value
                      ? null
                      : () => unawaited(
                          _clearToken(
                            title: i18n('gist_clear_token'),
                            message: i18n('gist_clear_token_confirm'),
                          ),
                        ),
                ),
            ]),
            if (!controller.isConfigured) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  i18n('gist_token_help'),
                  style: AppTextStyles.t12.copyWith(color: Theme.of(context).hintColor),
                ),
              ),
            ],
            if (controller.isConfigured) ...[
              const SizedBox(height: 20),
              context.buildGroupTitle(i18n('gist_actions')),
              context.buildModernCard([
                context.buildTile(
                  icon: Remix.cloud_off_line,
                  title: i18n('gist_backup_now'),
                  subtitle: controller.lastBackupAt.value.isEmpty
                      ? i18n('gist_never_backup')
                      : i18n('gist_last_backup', args: {'time': controller.lastBackupAt.v}),
                  isLong: true,
                  trailing: _busyIndicator('gist_backing_up'),
                  onTap: controller.isBusy.value ? null : () => unawaited(_backupNow()),
                ),
                context.buildTile(
                  icon: Remix.download_cloud_2_line,
                  title: i18n('gist_restore_latest'),
                  subtitle: i18n('gist_restore_latest_desc'),
                  isLong: true,
                  trailing: _busyIndicator('gist_restoring'),
                  onTap: controller.isBusy.value ? null : () => unawaited(_restoreLatest()),
                ),
                context.buildTile(
                  icon: Remix.refresh_line,
                  title: i18n('gist_refresh'),
                  subtitle: statusKey.isEmpty ? null : i18n(statusKey),
                  isLong: true,
                  subtitleColor: statusKey.endsWith('_failed') ? Theme.of(context).colorScheme.error : null,
                  onTap: controller.isBusy.value ? null : () => unawaited(controller.refreshSnapshots()),
                ),
              ]),
              const SizedBox(height: 20),
              context.buildGroupTitle(i18n('gist_snapshots')),
              context.buildModernCard([
                if (controller.snapshots.isEmpty)
                  context.buildTile(icon: Remix.inbox_line, title: i18n('gist_no_snapshot'), isLong: true),
                for (final snapshot in controller.snapshots)
                  context.buildTile(
                    icon: Remix.file_cloud_line,
                    title: snapshot.displayTime,
                    subtitle: identical(snapshot, controller.snapshots.first)
                        ? i18n('gist_snapshot_latest')
                        : snapshot.fileName,
                    isLong: true,
                    trailing: IconButton(
                      icon: Icon(Remix.delete_bin_line, color: Theme.of(context).colorScheme.error),
                      tooltip: i18n('gist_delete_snapshot'),
                      onPressed: controller.isBusy.value
                          ? null
                          : () => unawaited(_deleteSnapshot(snapshot)),
                    ),
                    onTap: controller.isBusy.value ? null : () => unawaited(_restoreSnapshot(snapshot)),
                  ),
              ]),
            ],
            const SizedBox(height: 32),
          ],
        );
      }),
    );
  }

  Widget? _busyIndicator(String key) {
    if (controller.isBusy.value && controller.statusKey.value == key) {
      return const SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return null;
  }

  void _reportFailure(String fallbackKey) {
    final detail = controller.errorDetail.value;
    ToastUtil.show(detail.isEmpty ? i18n(fallbackKey) : '${i18n(fallbackKey)}：$detail');
  }

  Future<bool?> _confirm({required String title, required String message}) {
    final context = Get.context;
    if (context == null) return Future<bool?>.value(false);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(i18n('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(i18n('confirm'))),
        ],
      ),
    );
  }

  Future<void> _backupNow() async {
    if (await controller.backupNow()) {
      ToastUtil.show(i18n('gist_backup_ok'));
      return;
    }
    _reportFailure('gist_backup_failed');
  }

  Future<void> _clearToken({required String title, required String message}) async {
    if (await _confirm(title: title, message: message) != true) return;
    await controller.clearToken();
  }

  Future<void> _restoreLatest() async {
    if (controller.snapshots.isEmpty) {
      ToastUtil.show(i18n('gist_no_snapshot'));
      return;
    }
    final confirmed = await _confirm(
      title: i18n('gist_restore_confirm_title'),
      message: i18n('gist_restore_confirm_message'),
    );
    if (confirmed != true) return;
    await _applyRestore();
  }

  Future<void> _restoreSnapshot(GistSnapshot snapshot) async {
    final confirmed = await _confirm(
      title: i18n('gist_restore_confirm_title'),
      message: '${i18n('gist_restore_confirm_message')}\n${snapshot.displayTime}',
    );
    if (confirmed != true) return;
    await _applyRestore(snapshot);
  }

  Future<void> _applyRestore([GistSnapshot? snapshot]) async {
    if (await controller.restore(snapshot)) {
      ToastUtil.show(i18n('gist_restore_ok'));
      return;
    }
    _reportFailure('gist_restore_failed');
  }

  Future<void> _deleteSnapshot(GistSnapshot snapshot) async {
    final confirmed = await _confirm(
      title: i18n('gist_delete_confirm_title'),
      message: i18n('gist_delete_confirm_message'),
    );
    if (confirmed != true) return;
    if (await controller.deleteSnapshot(snapshot)) {
      ToastUtil.show(i18n('gist_delete_ok'));
      return;
    }
    _reportFailure('gist_delete_failed');
  }

  Future<void> _showTokenDialog(BuildContext hostContext) async {
    if (!hostContext.mounted) return;
    final input = TextEditingController(text: controller.token.v);
    final saved = await showDialog<bool>(
      context: hostContext,
      builder: (dialogContext) => AlertDialog(
        title: Text(i18n('gist_token_dialog_title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: input,
                autofocus: true,
                obscureText: true,
                decoration: InputDecoration(labelText: i18n('gist_token_field_label')),
              ),
              const SizedBox(height: 12),
              Text(i18n('gist_token_help'), style: AppTextStyles.t12),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(i18n('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(i18n('confirm'))),
        ],
      ),
    );
    input.dispose();
    if (saved != true) return;
    final ok = await controller.saveToken(input.text);
    ToastUtil.show(ok ? i18n('gist_token_invalid_ok') : i18n('gist_token_invalid'));
  }
}
