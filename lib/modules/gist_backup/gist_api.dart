import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:pure_live/core/common/http_client.dart';

/// GitHub Gist 备份通道。
///
/// 全部快照都放在**同一个私有 Gist** 里，每份备份是该 Gist 下的一个文件，
/// 文件名带本地时间戳（`purelive_backup_20260928_103000.json`），
/// 因此恢复时可以按日期自由挑选，默认使用最新一份。
class GistApiException implements Exception {
  GistApiException(this.statusCode, this.detail);

  final int statusCode;
  final String detail;

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'GistApiException($statusCode): $detail';
}

/// 单份云备份快照（= 备份 Gist 中的一个文件）。
class GistSnapshot {
  const GistSnapshot({required this.fileName, required this.savedAt, this.size = 0});

  final String fileName;
  final DateTime savedAt;
  final int size;

  String get displayTime {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${savedAt.year}-${two(savedAt.month)}-${two(savedAt.day)} '
        '${two(savedAt.hour)}:${two(savedAt.minute)}:${two(savedAt.second)}';
  }
}

class GistApi {
  GistApi({required this.token, Dio? dio}) : _dio = dio ?? HttpClient.instance.dio;

  final String token;
  final Dio _dio;

  static const String host = 'https://api.github.com';
  static const String description = 'Pure Live 设置备份';
  static const String filePrefix = 'purelive_backup_';
  static const String fileSuffix = '.json';
  static const int pageSize = 100;

  Map<String, dynamic> get _headers => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'Content-Type': 'application/json',
  };

  Options _options({ResponseType type = ResponseType.json}) =>
      Options(headers: _headers, responseType: type, validateStatus: (_) => true);

  Future<Response<dynamic>> _send(Future<Response<dynamic>> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw GistApiException(error.response?.statusCode ?? 0, error.message ?? 'network error');
    }
  }

  Response<dynamic> _check(Response<dynamic> response) {
    final code = response.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw GistApiException(code, _detailOf(response.data));
    }
    return response;
  }

  static String _detailOf(dynamic body) {
    if (body is Map && body['message'] is String) return body['message'] as String;
    if (body is String) return body;
    return '';
  }

  /// 文件名（不含前后缀）→ 本地时间。
  static DateTime? parseTimestamp(String bareName) {
    final match = RegExp(r'^(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})').firstMatch(bareName);
    if (match == null) return null;
    int part(int index) => int.parse(match.group(index)!);
    return DateTime(part(1), part(2), part(3), part(4), part(5), part(6));
  }

  static String formatTimestamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}_'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }

  static bool isSnapshotFile(String name) =>
      name.startsWith(filePrefix) && name.endsWith(fileSuffix) && parseTimestamp(bareName(name)) != null;

  static String bareName(String fileName) =>
      fileName.substring(filePrefix.length, fileName.length - fileSuffix.length);

  /// 验证令牌是否可用（同时确认 Gist 读写权限）。
  Future<void> verifyToken() async {
    final response = _check(await _send(() => _dio.get('$host/user', options: _options())));
    final data = response.data;
    if (data is! Map || data['login'] is! String) {
      throw GistApiException(response.statusCode ?? 0, 'unexpected payload');
    }
  }

  /// 找出本应用的备份 Gist；没有则新建一个。
  ///
  /// 令牌被清空、重装或换机后不需要用户再填 gist id：按描述标识自动找回。
  Future<String> ensureBackupGist() async {
    for (var page = 1; page <= 10; page++) {
      final response = _check(
        await _send(
          () => _dio.get('$host/gists', queryParameters: {'per_page': pageSize, 'page': page}, options: _options()),
        ),
      );
      final data = response.data;
      if (data is! List) break;
      for (final item in data) {
        if (item is! Map) continue;
        if (item['description'] != description) continue;
        final id = item['id'];
        if (id is String && id.isNotEmpty) return id;
      }
      if (data.length < pageSize) break;
    }
    final created = _check(
      await _send(
        () => _dio.post(
          '$host/gists',
          data: jsonEncode({
            'description': description,
            'public': false,
            'files': {
              '${filePrefix}README$fileSuffix': {
                'content': 'Pure Live 设置备份。每个 purelive_backup_<时间>.json 是一份快照。',
              },
            },
          }),
          options: _options(),
        ),
      ),
    );
    final id = created.data is Map ? (created.data as Map)['id'] : null;
    if (id is! String || id.isEmpty) {
      throw GistApiException(created.statusCode ?? 0, 'missing gist id');
    }
    return id;
  }

  /// 读取 Gist 内全部快照，按时间倒序（第一条即最新）。
  Future<List<GistSnapshot>> listSnapshots(String gistId) async {
    final files = await _readFiles(gistId);
    final snapshots = <GistSnapshot>[];
    files.forEach((name, entry) {
      if (!isSnapshotFile(name)) return;
      final savedAt = parseTimestamp(bareName(name));
      if (savedAt == null) return;
      final size = entry is Map && entry['size'] is int ? entry['size'] as int : 0;
      snapshots.add(GistSnapshot(fileName: name, savedAt: savedAt, size: size));
    });
    snapshots.sort((a, b) => b.fileName.compareTo(a.fileName));
    return snapshots;
  }

  Future<Map<String, dynamic>> _readFiles(String gistId) async {
    final response = _check(await _send(() => _dio.get('$host/gists/$gistId', options: _options())));
    final data = response.data;
    final files = data is Map ? data['files'] : null;
    if (files is! Map) throw GistApiException(response.statusCode ?? 0, 'snapshot list unavailable');
    return Map<String, dynamic>.from(files);
  }

  /// 读取快照内容；内容被截断时回落到 raw_url。
  Future<String> readSnapshot(String gistId, String fileName) async {
    final files = await _readFiles(gistId);
    final entry = files[fileName];
    if (entry is! Map) {
      throw GistApiException(404, 'snapshot $fileName is missing');
    }
    final content = entry['content'];
    if (content is String && content.isNotEmpty) return content;
    final rawUrl = entry['raw_url'];
    if (rawUrl is String && rawUrl.isNotEmpty) return _downloadRaw(rawUrl);
    throw GistApiException(200, 'snapshot $fileName has no content');
  }

  Future<String> _downloadRaw(String rawUrl) async {
    final response = _check(
      await _send(
        () => _dio.get(rawUrl, options: _options(type: ResponseType.plain)),
      ),
    );
    final data = response.data;
    if (data is String) return data;
    throw GistApiException(response.statusCode ?? 0, 'raw download failed');
  }

  /// 写入一份新快照，并在同一次请求里删掉需要滚动清理的旧快照。
  Future<void> writeSnapshot(
    String gistId, {
    required String fileName,
    required String content,
    List<String> removeFileNames = const [],
  }) async {
    final files = <String, dynamic>{
      fileName: {'content': content},
      for (final stale in removeFileNames) stale: null,
    };
    _check(
      await _send(
        () => _dio.patch('$host/gists/$gistId', data: jsonEncode({'files': files}), options: _options()),
      ),
    );
  }

  Future<void> deleteSnapshot(String gistId, String fileName) async {
    await writeSnapshot(gistId, fileName: fileName, content: '', removeFileNames: [fileName]);
  }

  /// 本地时间 → 不重名的快照文件名。
  static String snapshotFileName(DateTime time, Set<String> taken) {
    final base = '$filePrefix${formatTimestamp(time)}';
    var candidate = '$base$fileSuffix';
    var index = 1;
    while (taken.contains(candidate)) {
      candidate = '$base-$index$fileSuffix';
      index++;
    }
    return candidate;
  }
}
