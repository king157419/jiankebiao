import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/native_bridge.dart';
import 'package:shu_schedule/features/widgets/widget_sync.dart';

/// v1.4.0 任务 C：两个桌面小组件（4×2 + 2×1「下一节」）的 Android 接线，钉死在文件层面。
///
/// Kotlin 里「显示哪一天 / 头部状态 / 下一节 / 重绘时刻」的逻辑由
/// `android/app/src/test/kotlin/.../WidgetTimeLogicTest.kt`（JVM 单测）覆盖，这里只核对
/// Dart 推送目标、Manifest、资源和闹钟用法这些「改一处忘一处」的地方。
void main() {
  const res = 'android/app/src/main/res';
  const kt = 'android/app/src/main/kotlin/cn/shu/schedule';
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();

  String read(String path) => File(path).readAsStringSync();

  test('refreshTargets 里的每个 Provider 都有 Kotlin 类和 Manifest receiver', () {
    for (final qualified in WidgetSync.refreshTargets) {
      expect(qualified, startsWith('cn.shu.schedule.widgets.'));
      final name = qualified.split('.').last;
      final source = File('$kt/widgets/$name.kt');
      expect(source.existsSync(), isTrue, reason: source.path);
      expect(
        source.readAsStringSync(),
        contains('class $name : ShuWidgetProvider()'),
      );

      final receiver = RegExp(
        'android:name="\\.widgets\\.$name"([\\s\\S]*?)</receiver>',
      ).firstMatch(manifest);
      expect(receiver, isNotNull, reason: name);
      final body = receiver!.group(1)!;
      expect(body, contains('android.appwidget.action.APPWIDGET_UPDATE'));
      final info = RegExp(r'android:resource="@xml/(\w+)"')
          .firstMatch(body)!
          .group(1)!;
      expect(File('$res/xml/$info.xml').existsSync(), isTrue, reason: info);
    }
  });

  test('2×1「下一节」：最小 110dp × 40dp、可调、布局 / 预览 / 文案齐全', () {
    final info = read('$res/xml/next_widget_info.xml');
    expect(info, contains('android:minWidth="110dp"'));
    expect(info, contains('android:minHeight="40dp"'));
    expect(info, contains('android:resizeMode="horizontal|vertical"'));
    expect(info, contains('android:initialLayout="@layout/widget_next"'));
    expect(
      info,
      contains('android:previewLayout="@layout/widget_next_preview"'),
    );
    expect(
      info,
      contains('android:previewImage="@drawable/widget_next_preview"'),
    );
    expect(File('$res/layout/widget_next_preview.xml').existsSync(), isTrue);
    expect(
      File('$res/drawable-nodpi/widget_next_preview.png').existsSync(),
      isTrue,
    );

    // 三行：课程名 / 时间 / 地点，没有列表。
    final layout = read('$res/layout/widget_next.xml');
    for (final id in <String>[
      'next_root',
      'next_bar',
      'next_name',
      'next_time',
      'next_location',
    ]) {
      expect(layout, contains('android:id="@+id/$id"'), reason: id);
    }
    expect(layout, isNot(contains('<ListView')));

    final strings = read('$res/values/strings.xml');
    expect(strings, contains('<string name="widget_next_label">下一节课</string>'));
    expect(
      strings,
      contains('<string name="widget_next_none">近期没有课程</string>'),
    );
    expect(strings, contains('name="widget_next_description"'));
    expect(
      strings,
      contains('<string name="widget_back_to_tomorrow">回到明天</string>'),
    );
  });

  // v1.5.0（PLAN-1.5 D4）：两种小组件都能从 App 里加，加上以后原生弹 Toast。
  group('App 内添加小组件：两个 provider + 成功回调', () {
    test('MainActivity：day → 4×2、next → 2×1，successCallback 是不可变的广播', () {
      final activity = read('$kt/MainActivity.kt');
      for (final needle in <String>[
        'call.argument<String>("provider")',
        'PIN_DAY = "day"',
        'PIN_NEXT = "next"',
        'PIN_DAY -> DayWidgetProvider::class.java',
        'PIN_NEXT -> NextWidgetProvider::class.java',
        'PendingIntent.getBroadcast(',
        'Intent(applicationContext, PinResultReceiver::class.java)',
        'PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE',
        'requestPinAppWidget(ComponentName(this, providerClass), null, successCallback)',
      ]) {
        expect(activity, contains(needle), reason: needle);
      }
      // 只有一处调用，而且 successCallback 不再是 null（v1.4.0 是 `null, null`）。
      expect(
        RegExp(r'requestPinAppWidget\(').allMatches(activity).length,
        1,
        reason: '只应有一处 requestPinAppWidget 调用',
      );
      // 不认识的 provider 直接返回 false，不能默默钉 4×2。
      expect(
        RegExp(
          r'else -> \{[^}]*return false',
          multiLine: true,
        ).hasMatch(activity),
        isTrue,
      );
    });

    test('PinResultReceiver：包根、不导出、Toast 文案在 strings.xml', () {
      // 放在包根而不是 widgets/：widgets/ 下的 REQUEST_* 计数和注释扫描只管小组件本身。
      final receiver = File('$kt/PinResultReceiver.kt');
      expect(receiver.existsSync(), isTrue);
      expect(File('$kt/widgets/PinResultReceiver.kt').existsSync(), isFalse);
      final source = receiver.readAsStringSync();
      expect(source, contains('class PinResultReceiver : BroadcastReceiver()'));
      expect(
        source,
        contains(
          'Toast.makeText(context, R.string.widget_pinned_toast, Toast.LENGTH_SHORT).show()',
        ),
      );
      expect(source, contains('MainActivity.onPinned?.invoke(provider)'));
      final activity = read('$kt/MainActivity.kt');
      expect(
        activity,
        contains('@Volatile var onPinned: ((String?) -> Unit)? = null'),
      );
      expect(activity, contains('invokeMethod("onWidgetPinned", provider)'));
      expect(activity, contains('onPinned = null'));

      final entry = RegExp(
        r'<receiver\s+android:name="\.PinResultReceiver"([^>]*)/>',
      ).firstMatch(manifest);
      expect(entry, isNotNull, reason: 'Manifest 里要有 .PinResultReceiver');
      expect(entry!.group(1), contains('android:exported="false"'));
      expect(entry.group(1), isNot(contains('intent-filter')));

      expect(
        read('$res/values/strings.xml'),
        contains('<string name="widget_pinned_toast">小组件已添加到桌面</string>'),
      );
    });

    test('Dart 侧 provider 常量和 Kotlin 一致', () {
      final activity = read('$kt/MainActivity.kt');
      expect(activity, contains('PIN_DAY = "${NativeBridge.pinDay}"'));
      expect(activity, contains('PIN_NEXT = "${NativeBridge.pinNext}"'));
    });
  });

  test('面板预览图：assets/widgets 和 drawable-nodpi 两份字节一致，pubspec 已登记', () {
    for (final name in <String>[
      'widget_day_preview.png',
      'widget_next_preview.png',
    ]) {
      final asset = File('assets/widgets/$name');
      final original = File('$res/drawable-nodpi/$name');
      expect(asset.existsSync(), isTrue, reason: asset.path);
      expect(
        original.existsSync(),
        isTrue,
        reason: '${original.path}（启动器预览还在用）',
      );
      expect(
        asset.readAsBytesSync(),
        original.readAsBytesSync(),
        reason: '改了一边的预览图，另一边也要同步：$name',
      );
    }
    expect(read('pubspec.yaml'), contains('    - assets/widgets/'));
  });

  test('小组件闹钟：每个 request code 都不同，只用非精确、不唤醒的 RTC', () {
    final codes = <String, String>{};
    for (final f in Directory(
      '$kt/widgets',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.kt'))) {
      final source = f.readAsStringSync();
      for (final m in RegExp(
        r'const val (REQUEST_\w+) = (0x[0-9A-Fa-f]+)',
      ).allMatches(source)) {
        final name = '${f.uri.pathSegments.last}:${m.group(1)}';
        final value = m.group(2)!.toLowerCase();
        expect(
          codes.containsKey(value),
          isFalse,
          reason: '$name 和 ${codes[value]} 撞了 request code $value',
        );
        codes[value] = name;
      }
      // 不申请也不用精确闹钟；RTC（不带 _WAKEUP）在休眠时不投递，不会为小组件唤醒设备。
      // 只查调用和常量引用（注释里提到 `setExactAndAllowWhileIdle` 是在解释为什么不用它）。
      final banned = RegExp(
        r'\.(setExact\w*|setAlarmClock)\(|AlarmManager\.(RTC_WAKEUP|ELAPSED_REALTIME_WAKEUP)',
      );
      expect(
        banned.allMatches(source).map((m) => m.group(0)).toList(),
        isEmpty,
        reason: f.path,
      );
    }
    // 4×2 和 2×1 各一个每日闹钟 + 一个边界闹钟。
    expect(codes.length, 4, reason: codes.toString());

    final base = read('$kt/widgets/ShuWidgetProvider.kt');
    expect(base, contains('alarmManager.set('));
    expect(base, contains('AlarmManager.RTC,'));
    expect(base, contains('action == ACTION_BOUNDARY_REFRESH'));
  });

  test('Kotlin 注释里不再有过时的「14 天」/「上大课表」', () {
    for (final f in Directory(
      '$kt/widgets',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.kt'))) {
      final source = f.readAsStringSync();
      expect(source, isNot(contains('上大课表')), reason: f.path);
      expect(source, isNot(contains('14 天')), reason: f.path);
    }
  });

  test('README：两种小组件都能在 App 里添加，弹不出确认框时从小组件列表拖', () {
    final readme = read('README.md');
    expect(readme, contains('下一节课'));
    expect(readme, contains('「设置 → 添加桌面小组件」'));
    expect(readme, contains('「下一节课 · 2×1」卡片的「添加到桌面」'));
    expect(readme, contains('小组件列表'));
    expect(readme, isNot(contains('只能从桌面的小组件列表添加')));
    expect(readme, isNot(contains('一键添加只钉 4×2')));
    expect(readme, isNot(contains('长按 App 图标')));
  });
}
