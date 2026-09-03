import 'dart:convert';
import 'dart:io';
import 'package:pure_live/common/utils/hive_pref_util.dart';

/// GitHub 私有 Gist 备份服务（纯 HTTP，无 Git 依赖）
/// - 数据量极小（JSON 几KB~十几KB），单 Gist 单文件正合适
/// - 首次上传自动创建并保存 gist_id，之后更新同一 Gist
/// - token 存 Hive 本地（gist_token），可随时清空
class GistBackupService {
  static const String _base = 'https://api.github.com';
  static const String fileName = 'pure_live_backup.json';

  static String? get token => HivePrefUtil.getString('gist_token');
  static String? get gistId => HivePrefUtil.getString('gist_id');

  static void setToken(String value) => HivePrefUtil.setString('gist_token', value);

  static void clearToken() => HivePrefUtil.remove('gist_token');

  /// 令牌有效性校验
  static Future<bool> verifyToken(String token) async {
    final code = await _request('GET', '/user', token: token, expect: {200});
    return code == 200;
  }

  /// 上传备份内容：已有 gist_id 则更新，否则创建
  static Future<String> upload(String token, String content) async {
    final id = gistId;
    if (id != null && id.isNotEmpty) {
      try {
        await _request('PATCH', '/gists/$id', token: token,
            body: {'files': {fileName: {'content': content}}}, expect: {200});
        return id;
      } on GistNotFoundException {
        // Gist 被删/失效 → 重新创建
      }
    }
    final resp = await _requestJson('POST', '/gists', token: token,
        body: {
          'description': 'PureLive 数据备份',
          'public': false,
          'files': {fileName: {'content': content}},
        },
        expect: {201, 200});
    final newId = resp['id'] as String?;
    if (newId == null) throw const GistException('创建 Gist 失败：响应缺少 id');
    HivePrefUtil.setString('gist_id', newId);
    return newId;
  }

  /// 读取备份内容
  static Future<String> read(String token) async {
    final id = gistId;
    if (id == null || id.isEmpty) throw const GistException('尚未上传过备份（缺少 Gist 编号）');
    final resp = await _requestJson('GET', '/gists/$id', token: token, expect: {200});
    final files = resp['files'] as Map<String, dynamic>? ?? {};
    final file = files[fileName] as Map<String, dynamic>?;
    final content = file?['content'] as String?;
    if (content == null || content.isEmpty) throw const GistException('云端备份内容为空');
    return content;
  }

  // =========================
  // http helpers
  // =========================
  static Future<int> _request(String method, String path,
      {String? token, Map<String, dynamic>? body, Set<int> expect = const {}}) async {
    final (_, code) = await _requestRaw(method, path, token: token, body: body);
    if (expect.isNotEmpty && !expect.contains(code)) {
      if (code == 404) throw const GistNotFoundException();
      throw GistException('请求失败 HTTP $code');
    }
    return code;
  }

  static Future<Map<String, dynamic>> _requestJson(String method, String path,
      {String? token, Map<String, dynamic>? body, Set<int> expect = const {}}) async {
    final (raw, code) = await _requestRaw(method, path, token: token, body: body);
    if (expect.isNotEmpty && !expect.contains(code)) {
      if (code == 404) throw const GistNotFoundException();
      if (code == 401 || code == 403) throw const GistException('Token 无效或无权限，请检查令牌');
      throw GistException('请求失败 HTTP $code');
    }
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw const GistException('响应解析失败');
    }
  }

  static Future<(String, int)> _requestRaw(String method, String path,
      {String? token, Map<String, dynamic>? body}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
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