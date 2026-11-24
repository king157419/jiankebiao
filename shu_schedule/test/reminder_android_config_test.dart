import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/privacy_policy.dart';
import 'package:shu_schedule/core/reminders/reminder_service.dart';

/// v1.4.0 B1 / B4：上课提醒的依赖、Android 配置与隐私说明，钉死在文件层面。
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();

  test('pubspec：flutter_local_notifications ^22.3.1 + timezone ^0.11.1，不加 flutter_timezone', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('  flutter_local_notifications: ^22.3.1'));
    expect(pubspec, contains('  timezone: ^0.11.1'));
    expect(
      RegExp(r'^\s+flutter_timezone:', multiLine: true).hasMatch(pubspec),
      isFalse,
    );
  });

  test(
    'build.gradle.kts：开启 core library desugaring（desugar_jdk_libs 2.1.4）',
    () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('isCoreLibraryDesugaringEnabled = true'));
      expect(
        gradle,
        contains(
          'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")',
        ),
      );
    },
  );

  test('Manifest：提醒权限 + 插件的两个 receiver；精确闹钟按官方写法 '
      'SCHEDULE_EXACT_ALARM(maxSdk 32) + USE_EXACT_ALARM（修复轮 P1-1）', () {
    for (final p in <String>[
      'POST_NOTIFICATIONS',
      'USE_EXACT_ALARM',
      'RECEIVE_BOOT_COMPLETED',
      'VIBRATE',
    ]) {
      expect(
        manifest,
        contains('<uses-permission android:name="android.permission.$p"/>'),
        reason: p,
      );
    }
    // developer.android.com/reference/android/Manifest.permission#USE_EXACT_ALARM：
    // 同时用两者时 SCHEDULE_EXACT_ALARM 要带 maxSdkVersion="32"。
    expect(
      manifest,
      contains(
        '<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" '
        'android:maxSdkVersion="32"/>',
      ),
    );
    expect(
      RegExp(r'android\.permission\.SCHEDULE_EXACT_ALARM"')
          .allMatches(manifest),
      hasLength(1),
      reason: '只声明一次，而且带 maxSdkVersion',
    );
    expect(
      manifest,
      contains(
        'android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"',
      ),
    );
    final boot = RegExp(
      r'ScheduledNotificationBootReceiver">([\s\S]*?)</receiver>',
    ).firstMatch(manifest)!.group(1)!;
    for (final action in <String>[
      'android.intent.action.BOOT_COMPLETED',
      'android.intent.action.MY_PACKAGE_REPLACED',
      'android.intent.action.QUICKBOOT_POWERON',
      'com.htc.intent.action.QUICKBOOT_POWERON',
    ]) {
      expect(
        boot,
        contains('<action android:name="$action"/>'),
        reason: action,
      );
    }
  });

  test('状态栏小图标：纯白单色矢量，keep.xml 保住它，名字和 Dart 端一致', () {
    final name = LocalNotificationsGateway.smallIcon;
    final icon = File('android/app/src/main/res/drawable/$name.xml');
    expect(icon.existsSync(), isTrue);
    final colors = RegExp(r'android:fillColor="([^"]+)"')
        .allMatches(icon.readAsStringSync())
        .map((m) => m.group(1))
        .toSet();
    expect(colors, <String>{'#FFFFFFFF'});
    final keep = File('android/app/src/main/res/raw/keep.xml')
        .readAsStringSync();
    expect(keep, contains('@drawable/$name'));
  });

  test('通知渠道 id', () {
    expect(ReminderChannels.classReminder, 'class_reminder');
    expect(ReminderChannels.classReminderName, '上课提醒');
    expect(ReminderChannels.eveningPreview, 'evening_preview');
    expect(ReminderChannels.eveningPreviewName, '明日预告');
  });

  // v1.5.0：隐私说明换成白话短文（PLAN-1.5 第 3 节），不再逐条列权限名和依赖名；
  // 完整的技术清单在根 README §七。这里改成两道门：隐私说明用系统设置里的名字
  // 提到提醒用的两个权限；清单里的权限集合钉死，新增权限时测试会提醒复核文案。
  test('隐私说明：用「通知」「闹钟和提醒」说清提醒的权限，提醒在手机本地生成', () {
    final md = File(PrivacyPolicy.assetPath).readAsStringSync();
    for (final must in <String>['「通知」', '「闹钟和提醒」', '上课提醒在手机本地生成']) {
      expect(md, contains(must), reason: '缺少：$must');
    }
    for (final bad in <String>[
      'android.permission',
      'USE_EXACT_ALARM',
      'SCHEDULE_EXACT_ALARM',
      'Android 1',
      'SDK',
      'JSON',
    ]) {
      expect(md, isNot(contains(bad)), reason: '隐私说明里出现了术语「$bad」');
    }
  });

  test('Manifest 的权限集合（新增权限请复核 privacy.md 和根 README）', () {
    final declared = RegExp(
      r'<uses-permission android:name="android\.permission\.([A-Z_]+)"',
    ).allMatches(manifest).map((m) => m.group(1)!).toSet();
    expect(declared, <String>{
      'INTERNET',
      'POST_NOTIFICATIONS',
      'SCHEDULE_EXACT_ALARM',
      'USE_EXACT_ALARM',
      'RECEIVE_BOOT_COMPLETED',
      'VIBRATE',
    }, reason: '新增权限请复核 privacy.md（「用到的权限」一段）和根 README 的权限清单');
  });

  // 测试缺口 4：精确闹钟的说法不能回退成「晚几分钟」（非精确闹钟的窗口最长 1 小时，
  // 见 developer.android.com/develop/background-work/services/alarms/schedule）。
  // v1.5.0（D7）：提醒页和隐私说明不再写技术细节（「1 小时」只留在两份 README 里）。
  test('文案：不写「晚几分钟」；README 写清最多 1 小时；提醒页不出现权限名和系统版本', () {
    final page = File('lib/features/settings/reminder_settings_page.dart')
        .readAsStringSync();
    final files = <String, String>{
      'reminder_settings_page.dart': page,
      'privacy.md': File(PrivacyPolicy.assetPath).readAsStringSync(),
      '根 README.md': File('../README.md').readAsStringSync(),
      'shu_schedule/README.md': File('README.md').readAsStringSync(),
    };
    for (final e in files.entries) {
      for (final bad in <String>['晚几分钟', '推迟几分钟', '可能晚一点']) {
        expect(e.value, isNot(contains(bad)), reason: '${e.key} 里还有「$bad」');
      }
    }
    for (final readme in <String>['根 README.md', 'shu_schedule/README.md']) {
      expect(files[readme], contains('1 小时'), reason: '$readme 没写最多 1 小时');
    }
    // 只看字符串字面量（注释里可以保留技术背景）。
    final literals = RegExp(r"'([^'\n]*)'")
        .allMatches(
          page
              .split('\n')
              .where((l) => !l.trimLeft().startsWith('//'))
              .join('\n'),
        )
        .map((m) => m.group(1)!)
        .join('\n');
    for (final bad in <String>[
      'USE_EXACT_ALARM',
      'SCHEDULE_EXACT_ALARM',
      'Android 1',
      '精确闹钟',
      '1 小时',
    ]) {
      expect(literals, isNot(contains(bad)), reason: '提醒页字符串里还有「$bad」');
    }
    expect(page, contains('（系统可能让提醒晚到）'));
    expect(
      files['根 README.md']!,
      isNot(contains('能按时到，正式提醒就能到')),
      reason: 'review-G P1-1：删掉这句因果推断',
    );
  });
}
