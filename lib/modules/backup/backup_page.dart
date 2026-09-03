import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pure_live/plugins/file_utils.dart';
import 'package:pure_live/common/services/gist_backup_service.dart';
import 'package:pure_live/common/services/settings/backup_controller.dart';
import 'package:pure_live/modules/backup/scan_page.dart';
import 'package:pure_live/common/global/app_path_manager.dart';
import 'package:pure_live/plugins/backup_recovery_service.dart';
import 'package:pure_live/common/services/settings/log_controller.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final LogController logController = LogController.to;
  String get backupDirectory => SettingsService.to.backup.backupDirectory.v;

  Future<void> _openLogDirectory() async {
    try {
      Directory logDir;
      if (Platform.isAndroid) {
        final dir = await getDownloadsDirectory();
        logDir = Directory(path.join(dir!.path, AppPathManager.dirLogs));
      } else {
        logDir = await AppPathManager().getDir(AppPathManager.dirLogs);
      }

      if (await logDir.exists()) {
        FileUtils.openFileOrUrl(path.join(logDir.path, 'log'));
      } else {
        ToastUtil.show(i18n('log_dir_not_exist'));
      }
    } catch (e) {
      ToastUtil.show(i18n('open_log_dir_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n("backup_recover"))),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          context.buildGroupTitle(i18n("cloud_backup")),
          context.buildModernCard([
            // ★ Gist 云备份（私有 Gist，替代原 Firebase 云备份）
            context.buildTile(
              icon: Remix.github_line,
              title: i18n("gist_backup"),
              subtitle: GistBackupService.token == null || GistBackupService.token!.isEmpty
                  ? i18n("gist_setup")
                  : '${i18n("gist_ready")} · ${_maskToken(GistBackupService.token!)}',
              trailing: Icon(Remix.arrow_right_s_line, color: Theme.of(context).colorScheme.outline),
              onTap: _showGistConfigDialog,
            ),
            context.buildTile(
              icon: Remix.cloud_upload_line,
              title: i18n("upload_backup"),
              subtitle: i18n("upload_backup_subtitle"),
              onTap: _uploadToGist,
            ),
            context.buildTile(
              icon: Remix.cloud_download_line,
              title: i18n("restore_from_gist"),
              subtitle: i18n("restore_from_gist_subtitle"),
              onTap: _restoreFromGist,
            ),
            context.buildTile(
              icon: Remix.web_line,
              title: i18n("webdav"),
              subtitle: i18n("backup_to_webdav"),
              onTap: () => Get.toNamed(RoutePath.kWebDavPage),
            ),
            if (Platform.isAndroid || Platform.isIOS)
              context.buildTile(
                icon: Remix.qr_code_line,
                title: i18n("sync_tv_data"),
                subtitle: i18n("sync_tv_data_subtitle"),
                onTap: () => Get.to(() => const ScanCodePage()),
              ),
          ]),
            const SizedBox(height: 20),
            context.buildGroupTitle(i18n("local_backup")),
            context.buildModernCard([
              context.buildTile(
                icon: Remix.file_download_line,
                title: i18n("create_backup"),
                subtitle: i18n("create_backup_subtitle"),
                onTap: () async {
                  if (backupDirectory.isEmpty) {
                    ToastUtil.show(i18n('please_set_backup_directory'));
                    return;
                  }
                  await BackupRecoveryService().createAppSettingsBackup(backupDirectory);
                },
              ),
              context.buildTile(
                icon: Remix.file_upload_line,
                title: i18n("recover_backup"),
                subtitle: i18n("recover_backup_subtitle"),
                onTap: () => BackupRecoveryService().recoverSettingsFromFile(),
              ),
            ]),
            const SizedBox(height: 20),
            context.buildGroupTitle(i18n("backup_settings")),
            context.buildModernCard([
              context.buildTile(
                icon: Remix.folder_open_line,
                title: i18n("backup_directory"),
                subtitle: backupDirectory.isEmpty ? i18n('please_set_backup_directory') : backupDirectory,
                onTap: () async {
                  await BackupRecoveryService().updateBackupDirectory();
                },
              ),
            ]),
            const SizedBox(height: 20),
            context.buildGroupTitle(i18n("log_manage")),
            context.buildModernCard([
              context.buildTile(
                icon: Remix.file_text_line,
                title: i18n("enable_local_log"),
                subtitle: i18n("enable_local_log_desc"),
                trailing: Switch(
                  value: logController.storedEnableLog.v,
                  onChanged: (val) => logController.storedEnableLog.v = val,
                ),
                onTap: () => logController.storedEnableLog.v = !logController.storedEnableLog.v,
              ),
              Obx(() {
                if (logController.serverPort.value == 0) return const SizedBox.shrink();
                final String displayAddress = logController.serverAddress.value == '0.0.0.0'
                    ? 'localhost'
                    : logController.serverAddress.value;
                final String urlStr = 'http://$displayAddress:${logController.serverPort.value}';
                return context.buildTile(
                  icon: Remix.global_line,
                  title: i18n("view_logs_in_browser"),
                  subtitle: urlStr,
                  trailing: const Icon(Remix.arrow_right_s_line),
                  onTap: () async {
                    final Uri uri = Uri.parse(urlStr);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                );
              }),

              context.buildTile(
                icon: Remix.folder_open_line,
                title: i18n("open_log_dir"),
                subtitle: i18n("open_log_dir_desc"),
                onTap: _openLogDirectory,
              ),
            ]),
            const SizedBox(height: 32),
          ],
        ),
    );
  }

  // ==================== Gist 云备份 ====================

  String _maskToken(String token) {
    if (token.length <= 6) return '****';
    return '${token.substring(0, 3)}...${token.substring(token.length - 3)}';
  }

  Future<void> _showGistConfigDialog() async {
    final controller = TextEditingController(text: GistBackupService.token ?? '');
    final hasToken = (GistBackupService.token?.isNotEmpty ?? false);
    await showDialog<void>(
      context: Get.context!,
      builder: (context) => AlertDialog(
        title: Text(i18n("gist_backup")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              obscureText: true,
              decoration: InputDecoration(
                labelText: i18n("gist_token_hint"),
                hintText: 'github_pat_...',
              ),
            ),
            const SizedBox(height: 8),
            Text(i18n("gist_token_desc"), style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          if (hasToken)
            TextButton(
              onPressed: () async {
                GistBackupService.clearToken();
                ToastUtil.show(i18n("gist_token_cleared"));
                Navigator.of(context).pop();
              },
              child: Text(i18n("clear"), style: const TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(i18n("cancel")),
          ),
          ElevatedButton(
            onPressed: () async {
              final value = controller.text.trim();
              if (value.isEmpty) {
                ToastUtil.show(i18n("gist_token_hint"));
                return;
              }
              // 校验令牌
              try {
                final ok = await GistBackupService.verifyToken(value);
                if (!ok) {
                  ToastUtil.show(i18n("gist_invalid_token"));
                  return;
                }
              } catch (_) {
                ToastUtil.show(i18n("gist_invalid_token"));
                return;
              }
              GistBackupService.setToken(value);
              Navigator.of(context).pop();
              ToastUtil.show(i18n("gist_ready"));
            },
            child: Text(i18n("save")),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadToGist() async {
    final token = GistBackupService.token;
    if (token == null || token.isEmpty) {
      ToastUtil.show(i18n("gist_setup"));
      return;
    }
    try {
      final backup = Get.find<BackupController>();
      final content = jsonEncode(backup.exportAllSettings());
      final id = await GistBackupService.upload(token, content);
      ToastUtil.show('${i18n("upload_backup")} ✅ gist:$id');
    } on GistException catch (e) {
      ToastUtil.show('${i18n("gist_error")}: ${e.message}');
    } catch (e) {
      ToastUtil.show('${i18n("gist_error")}: $e');
    }
  }

  Future<void> _restoreFromGist() async {
    final token = GistBackupService.token;
    if (token == null || token.isEmpty) {
      ToastUtil.show(i18n("gist_setup"));
      return;
    }
    final confirm = await showDialog<bool>(
      context: Get.context!,
      builder: (context) => AlertDialog(
        title: Text(i18n("restore_from_gist")),
        content: Text(i18n("restore_confirm")),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(i18n("cancel"))),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: Text(i18n("confirm"))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final content = await GistBackupService.read(token);
      final data = jsonDecode(content) as Map<String, dynamic>;
      Get.find<BackupController>().importAllSettings(data);
      ToastUtil.show(i18n("gist_restored"));
    } on GistException catch (e) {
      ToastUtil.show('${i18n("gist_error")}: ${e.message}');
    } catch (e) {
      ToastUtil.show('${i18n("gist_error")}: $e');
    }
  }
}
