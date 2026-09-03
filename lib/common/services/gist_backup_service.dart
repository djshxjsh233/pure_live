import 'dart:convert';
import 'dart:io';
import 'package:pure_live/common/utils/hive_pref_util.dart';

/// 备份条目（恢复列表项）
class GistBackupEntry {
  final String id;
  final String name;
  final int size;
  final bool isLatest;

  GistBackupEntry(this.id, this.name, this.size, {this.isLatest = false});

  /// 由 backup_20260903_1030.json → 2026-09-03 10:30
  String get dateLabel {
    if (name == GistBackupService.fileName) return '';
    final m = RegExp(r'backup_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})\.json').firstMatch(name);
    if (m == null) return name;
    return '${m[1]}-${m[2]}-${m[3]} ${m[4]}:${m[5]}';
  }
}

/// GitHub 私有 Gist 备份服务（纯 HTTP，无 Git 依赖）
/// - 单 Gist 多文件：latest(pure_live_backup.json) + 时间戳快照(backup_*.json)
/// - 上传自动保留最近 N 份快照（超出删最旧）
/// - gist_id 丢失(清数据/换机)时自动按文件名在 token 名下找回
class GistBackupService {
  static const String _base = 'https://api.github.com';
  static const String fileName = 'pure_live_backup.json';
  static const String snapshotPrefix = 'backup_';
  static const int keepLatestCount = 10;

  static String? get token => HivePrefUtil.getString('gist_token');
  static String? get gistId => HivePrefUtil.getString('gist_id');

  static void setToken(String value) => HivePrefUtil.setString('gist_token', value);

  static void clearToken() => HivePrefUtil.remove('gist_token');

  /// 令牌有效性校验
  static Future<bool> verifyToken(String token) async {
    final code = await _request('GET', '/user', token: token, expect: {200});
    return code == 200;
  }

  /// 上传：写 latest + 新增时间戳快照，保留最近 keepLatestCount 份
  static Future<String> upload(String token, String content) async {
    final id = (await _resolveGist(token, createIfMissing: true)) ??
      (throw const GistException('创建 Gist 失败：无法确定编号'));

    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final ts = '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';

    final files = <String, dynamic>{
      fileName: {'content': content},
      '$snapshotPrefix$ts.json': {'content': content},
    };

    // 清理：保留最近 keepLatestCount 份 backup_*.json
    try {
      final gist = await _requestJson('GET', '/gists/$id', token: token, expect: {200});
      final snapshots = (gist['files'] as Map<String, dynamic>? ?? {})
          .keys
          .where((k) => k.startsWith(snapshotPrefix) && k.endsWith('.json'))
          .toList()
        ..sort();
      while (snapshots.length >= keepLatestCount) {
        final oldest = snapshots.removeAt(0);
        files[oldest] = null; // null = 删除该文件
      }
    } catch (_) {}

    await _request('PATCH', '/gists/$id', token: token, body: {'files': files}, expect: {200});
    return id;
  }

  /// 列出云端所有备份（最新在前，含 latest 与历史快照）
  static Future<List<GistBackupEntry>> listBackups(String token) async {
    final id = await _resolveGist(token, createIfMissing: false);
    if (id == null) return const [];
    final gist = await _requestJson('GET', '/gists/$id', token: token, expect: {200});
    final files = gist['files'] as Map<String, dynamic>? ?? {};

    final entries = <GistBackupEntry>[];
    for (final e in files.entries) {
      final name = e.key;
      final size = (e.value as Map<String, dynamic>?)?['size'] as int? ?? 0;
      if (name == fileName) {
        entries.add(GistBackupEntry(id, name, size, isLatest: true));
      } else if (name.startsWith(snapshotPrefix) && name.endsWith('.json')) {
        entries.add(GistBackupEntry(id, name, size));
      }
    }
    entries.sort((a, b) {
      if (a.isLatest != b.isLatest) return a.isLatest ? -1 : 1; // 最新置顶
      return (b.name.length != a.name.length)
          ? b.name.length - a.name.length
          : b.name.compareTo(a.name); // 时间戳字符序倒序
    });
    return entries;
  }

  /// 读取指定备份文件内容（默认最新）
  static Future<String> read(String token, {String? file}) async {
    final id = await _resolveGist(token, createIfMissing: false);
    if (id == null) throw const GistException('云端没有找到备份（Gist 缺失或文件名被改）');
    final name = file ?? fileName;
    final resp = await _requestJson('GET', '/gists/$id', token: token, expect: {200});
    final files = resp['files'] as Map<String, dynamic>? ?? {};
    final f = files[name] as Map<String, dynamic>?;
    final content = f?['content'] as String?;
    if (content == null || content.isEmpty) throw const GistException('该备份内容为空');
    return content;
  }

  /// 解析自家备份 Gist id（缓存优先 → token 名下按文件名找回 → 创建）
  static Future<String?> _resolveGist(String token, {required bool createIfMissing}) async {
    final cached = gistId;
    if (cached != null && cached.isNotEmpty && await _gistExists(token, cached)) {
      return cached;
    }
    final found = await _findByFileName(token);
    if (found != null) {
      HivePrefUtil.setString('gist_id', found);
      return found;
    }
    if (!createIfMissing) return null;

    final resp = await _requestJson('POST', '/gists', token: token,
        body: {
          'description': 'PureLive 数据备份',
          'public': false,
          'files': {fileName: {'content': '{}'}},
        },
        expect: {201, 200});
    final newId = resp['id'] as String?;
    if (newId == null) throw const GistException('创建 Gist 失败：响应缺少 id');
    HivePrefUtil.setString('gist_id', newId);
    return newId;
  }

  static Future<bool> _gistExists(String token, String id) async {
    try {
      await _request('GET', '/gists/$id', token: token, expect: {200});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 在 token 名下按文件名找回备份 Gist
  static Future<String?> _findByFileName(String token) async {
    final resp = await _requestJson('GET', '/gists?per_page=100', token: token, expect: {200});
    final list = resp as List<dynamic>? ?? [];
    for (final item in list) {
      final g = item as Map<String, dynamic>;
      final files = g['files'] as Map<String, dynamic>? ?? {};
      if (files.containsKey(fileName) || files.keys.any((k) => k.startsWith(snapshotPrefix))) {
        return g['id'] as String?;
      }
    }
    return null;
  }

  // =========================
  // http helpers
  // =========================
  static Future<int> _request(String method, String path,
      {String? token, Map<String, dynamic>? body, Set<int> expect = const {}}) async {
    final (_, code) = await _requestRaw(method, path, token: token, body: body);
    if (expect.isNotEmpty && !expect.contains(code)) {
      if (code == 404) throw const GistNotFoundException();
      _throwByCode(code);
    }
    return code;
  }

  static Future<dynamic> _requestJson(String method, String path,
      {String? token, Map<String, dynamic>? body, Set<int> expect = const {}}) async {
    final (raw, code) = await _requestRaw(method, path, token: token, body: body);
    if (expect.isNotEmpty && !expect.contains(code)) {
      if (code == 404) throw const GistNotFoundException();
      _throwByCode(code);
    }
    try {
      return jsonDecode(raw);
    } catch (_) {
      throw const GistException('响应解析失败');
    }
  }

  static Never _throwByCode(int code) {
    if (code == 401 || code == 403) {
      throw const GistException('令牌缺少 Gists 读写权限（GitHub → Settings → Developer settings → Fine-grained token → 勾选 Gists: Read and write）');
    }
    throw GistException('请求失败 HTTP $code');
  }

  static Future<(String, int)> _requestRaw(String method, String path,
      {String? token, Map<String, dynamic>? body}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final uri = Uri.parse('$_base$path');
      final request = switch (method) {
        'POST' => await client.postUrl(uri),
        'PATCH' => await client.patchUrl(uri),
        'PUT' => await client.putUrl(uri),
        _ => await client.getUrl(uri),
      };
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'token $token');
      }
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'pure_live');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final resp = await request.close();
      final text = await resp.transform(utf8.decoder).join();
      return (text, resp.statusCode);
    } finally {
      client.close(force: true);
    }
  }
}

class GistException implements Exception {
  final String message;
  const GistException(this.message);
  @override
  String toString() => message;
}

/// Gist 不存在（可重新创建）
class GistNotFoundException extends GistException {
  const GistNotFoundException() : super('Gist 不存在');
}