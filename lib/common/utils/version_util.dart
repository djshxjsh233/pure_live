import 'package:package_info_plus/package_info_plus.dart';

/// 版本信息工具（仅保留版本号展示，原作者的更新检查/联系方式已全部移除）
class VersionUtil {
  static PackageInfo? _packageInfo;

  static Future<void> initPackageInfo() async {
    _packageInfo ??= await PackageInfo.fromPlatform();
  }

  static String get version => _packageInfo?.version ?? '0.0.0';
}
