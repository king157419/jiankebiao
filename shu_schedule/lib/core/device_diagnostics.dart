import 'package:package_info_plus/package_info_plus.dart';

import 'app_brand.dart';
import 'native_bridge.dart';

/// 「反馈 → 复制诊断信息」的内容：App 版本、Android 版本、机型。
///
/// 不含任何课表、学号、姓名；只在用户点「复制」时进剪贴板，App 不会自己发出去。
class DeviceDiagnostics {
  DeviceDiagnostics._();

  /// 拼诊断文本（纯函数）。拿不到的字段写「未知」。
  static String format({
    required String appVersion,
    String? buildNumber,
    Map<String, Object?> device = const <String, Object?>{},
  }) {
    String field(String key) {
      final v = device[key];
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? '未知' : s;
    }

    final build = (buildNumber == null || buildNumber.isEmpty)
        ? ''
        : '（$buildNumber）';
    final sdk = device['sdkInt'] == null ? '' : '（API ${field('sdkInt')}）';
    final maker = field('manufacturer');
    final model = field('model');
    final brand = field('brand');
    final makerText =
        brand != '未知' && brand.toLowerCase() != maker.toLowerCase()
        ? '$maker / $brand'
        : maker;
    return <String>[
      '${AppBrand.name} v$appVersion$build',
      'Android ${field('release')}$sdk',
      '机型：$makerText $model',
    ].join('\n');
  }

  /// 读本机信息并拼好（package_info_plus + [NativeBridge.deviceInfo]）。
  static Future<String> collect({NativeBridge? bridge}) async {
    var version = appVersion;
    String? build;
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) version = info.version;
      build = info.buildNumber;
    } catch (_) {
      // 读不到就用编译进来的版本号。
    }
    final device = await (bridge ?? NativeBridge.instance).deviceInfo();
    return format(appVersion: version, buildNumber: build, device: device);
  }
}
