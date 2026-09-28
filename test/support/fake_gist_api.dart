import 'package:pure_live/modules/gist_backup/gist_api.dart';

/// 不发起任何网络请求的 Gist 桩件：只覆盖控制器用到的五个入口。
class FakeGistApi extends GistApi {
  FakeGistApi({this.verifyFails = false, List<GistSnapshot>? initial, this.rawContent = '{}', this.gistId = 'gist-1'})
    : files = List<GistSnapshot>.from(initial ?? const []),
      super(token: 'fake-token');

  bool verifyFails;
  String rawContent;
  String gistId;
  final List<GistSnapshot> files;
  final List<String> written = [];
  final List<String> removed = [];
  final List<String> readNames = [];
  int ensureCalls = 0;

  @override
  Future<void> verifyToken() async {
    if (verifyFails) throw GistApiException(401, 'Bad credentials');
  }

  @override
  Future<String> ensureBackupGist() async {
    ensureCalls++;
    return gistId;
  }

  @override
  Future<List<GistSnapshot>> listSnapshots(String id) async {
    if (id != gistId) throw GistApiException(404, 'Not Found');
    final copy = List<GistSnapshot>.from(files);
    copy.sort((a, b) => b.fileName.compareTo(a.fileName));
    return copy;
  }

  @override
  Future<String> readSnapshot(String id, String fileName) async {
    readNames.add(fileName);
    if (!files.any((item) => item.fileName == fileName)) {
      throw GistApiException(404, 'Not Found');
    }
    return rawContent;
  }

  @override
  Future<void> writeSnapshot(
    String id, {
    required String fileName,
    required String content,
    List<String> removeFileNames = const [],
  }) async {
    written.add(fileName);
    removed.addAll(removeFileNames);
    files
      ..removeWhere((item) => removeFileNames.contains(item.fileName))
      ..add(GistSnapshot(fileName: fileName, savedAt: DateTime(2026, 1, 1)));
  }

  @override
  Future<void> deleteSnapshot(String id, String fileName) async {
    removed.add(fileName);
    files.removeWhere((item) => item.fileName == fileName);
  }
}
