import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/services/gist_backup_service.dart';
import 'package:pure_live/common/services/settings/backup_controller.dart';

/// github-gist 云备份下级页：令牌管理 + 备份 + 恢复（列表自选）
class GistBackupPage extends StatefulWidget {
  const GistBackupPage({super.key});

  @override
  State<GistBackupPage> createState() => _GistBackupPageState();
}

class _GistBackupPageState extends State<GistBackupPage> {
  bool get _hasToken => (GistBackupService.token?.isNotEmpty ?? false);

  String _maskToken(String token) {
    if (token.length <= 6) return '****';
    return '${token.substring(0, 3)}...${token.substring(token.length - 3)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(i18n("gist_backup"))),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          context.buildGroupTitle(i18n("gist_token_config")),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.github_line,
              title: _hasToken ? '${i18n("gist_ready")} · ${_maskToken(GistBackupService.token!)}' : i18n("gist_setup"),
              subtitle: _hasToken ? i18n("gist_token_manage_hint") : i18n("gist_config_token"),
              trailing: Icon(Remix.arrow_right_s_line, color: theme.colorScheme.outline),
              onTap: _showTokenDialog,
            ),
          ]),
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n("gist_operations")),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.file_upload_line,
              title: i18n("upload_backup"),
              subtitle: i18n("upload_backup_subtitle"),
              onTap: _upload,
            ),
            context.buildTile(
              icon: Remix.file_download_line,
              title: i18n("restore_from_gist"),
              subtitle: i18n("restore_from_gist_subtitle"),
              onTap: _restore,
            ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ==================== 令牌 ====================
  Future<void> _showTokenDialog() async {
    final controller = TextEditingController(text: GistBackupService.token ?? '');
    await showDialog<void>(
      context: Get.context!,
      builder: (context) => AlertDialog(
        title: Text(_hasToken ? i18n("gist_change_token") : i18n("gist_config_token")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              obscureText: true,
              decoration: InputDecoration(
                labelText: i18n("gist_token_hint"),
                hintText: 'github_pat_...',
              ),
            ),
            const SizedBox(height: 10),
            Text(i18n("gist_token_desc"),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.6)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n("cancel"))),
          if (_hasToken)
            TextButton(
              onPressed: () async {
                GistBackupService.clearToken();
                Navigator.of(context).pop();
                if (mounted) setState(() {});
                ToastUtil.show(i18n("gist_token_cleared"));
              },
              child: Text(i18n("clear"), style: const TextStyle(color: Colors.red)),
            ),
          ElevatedButton(
            onPressed: () async {
              final value = controller.text.trim();
              if (value.isEmpty) {
                ToastUtil.show(i18n("gist_token_hint"));
                return;
              }
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
              if (mounted) setState(() {});
              ToastUtil.show(i18n("gist_ready"));
            },
            child: Text(i18n("save")),
          ),
        ],
      ),
    );
  }

  // ==================== 备份 ====================
  Future<void> _upload() async {
    final token = GistBackupService.token;
    if (token == null || token.isEmpty) {
      ToastUtil.show(i18n("gist_setup"));
      return;
    }
    try {
      final backup = Get.find<BackupController>();
      final content = jsonEncode(backup.exportAllSettings());
      final id = await GistBackupService.upload(token, content);
      final kb = (content.length / 1024).toStringAsFixed(1);
      ToastUtil.show('${i18n("upload_backup")} ✅ ${kb}KB · gist:$id');
    } on GistException catch (e) {
      ToastUtil.show('${i18n("gist_error")}: ${e.message}');
    } catch (e) {
      ToastUtil.show('${i18n("gist_error")}: $e');
    }
  }

  // ==================== 恢复 ====================
  Future<void> _restore() async {
    final token = GistBackupService.token;
    if (token == null || token.isEmpty) {
      ToastUtil.show(i18n("gist_setup"));
      return;
    }
    try {
      final entries = await GistBackupService.listBackups(token);
      if (entries.isEmpty) {
        ToastUtil.show(i18n("gist_no_backup"));
        return;
      }
      final selected = await showDialog<GistBackupEntry>(
        context: Get.context!,
        builder: (context) => SimpleDialog(
          title: Text(i18n("restore_from_gist")),
          children: [
            for (final e in entries)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(e),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(e.isLatest ? Remix.star_fill : Remix.time_line,
                          size: 18, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          e.isLatest
                              ? '${i18n("gist_latest")} · ${(e.size / 1024).toStringAsFixed(1)}KB'
                              : '${e.dateLabel} · ${(e.size / 1024).toStringAsFixed(1)}KB',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 4),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n("cancel"))),
          ],
        ),
      );
      if (selected == null) return;

      final confirm = await showDialog<bool>(
        context: Get.context!,
        builder: (context) => AlertDialog(
          title: Text(i18n("restore_from_gist")),
          content: Text(
              '${i18n("restore_confirm")}\n\n${selected.isLatest ? i18n("gist_latest") : selected.dateLabel}'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(i18n("cancel"))),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: Text(i18n("confirm"))),
          ],
        ),
      );
      if (confirm != true) return;

      final content = await GistBackupService.read(token, file: selected.name);
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