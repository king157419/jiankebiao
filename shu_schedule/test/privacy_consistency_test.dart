import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// v1.4.0 修复轮（review-G 测试缺口 7 / P3-7）：关于页里联网说法的一致性。
///
/// v1.5.0 删掉了首次启动的隐私同意框，「同意框 ↔ privacy.md 第二节」那条用例随之删除；
/// 隐私说明页本身的测试在 `privacy_and_about_test.dart`。
void main() {
  test('关于页：「不带课表或个人信息」只说检查更新与假期表；教务导入单独写（P3-7）', () {
    final about = File('lib/features/settings/about_page.dart')
        .readAsStringSync();
    expect(about, contains('只在你从教务导入、检查更新、更新假期表时联网。'));
    expect(about, contains('检查更新和更新假期表的请求里不带课表或个人信息'));
    expect(about, contains('账号密码只提交给学校教务系统'));
    expect(
      about,
      isNot(contains('更新假期表时联网，请求里不带课表或个人信息')),
      reason: '旧说法把教务导入也算进「不带个人信息」',
    );
  });

  test('关于页（v1.5.0 R1-1 / R1-10）：周次不对指顶部「第 N 周」，四句白话无技术词', () {
    final about = File('lib/features/settings/about_page.dart')
        .readAsStringSync();
    expect(about, contains('周次不对：点课表顶部的「第 N 周」→「本周不是第 N 周？点这里校正」。'));
    expect(about, isNot(contains('必须是第 1 周的周一')));
    expect(about, contains('没有广告，没有服务器，不用注册账号。'));
    expect(about, contains('课表、作息、主题设置都只存在这台手机里，不会上传。'));
    expect(about, contains('1. 点课表页右上角的 ⋮，选「从教务导入」，再选你的学校。'));
    expect(about, contains('3. 登录成功后点底部的「一键导入课表」，应用会读取当前学期课表。'));
    expect(about, isNot(contains('后端服务器')));
    expect(about, isNot(contains('应用目录')));
  });

  test('用户可见文案统一叫「假期表」（v1.5.0 任务 E）：lib 字符串和 Android 资源里没有别的叫法', () {
    // assets/privacy.md 按 PLAN-1.5 第 3 节逐字照抄（「放假 / 调休日期表」），不在扫描范围内；
    // 注释不算用户可见文案。
    const old = <String>['假日表', '节假日表', '放假日期表', '调休日期表'];
    final literal = RegExp(r"'([^'\n]*)'");
    final offenders = <String>[];
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        for (final m in literal.allMatches(lines[i])) {
          final s = m.group(1)!;
          if (old.any(s.contains)) {
            offenders.add('${f.path}:${i + 1}: $s');
          }
        }
      }
    }
    for (final f in Directory(
      'android/app/src/main/res',
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.xml')) continue;
      final text = f.readAsStringSync();
      for (final o in old) {
        if (text.contains(o)) offenders.add('${f.path}: $o');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
    // 扫描本身是有效的：新叫法确实出现在 lib 的字符串里。
    expect(
      File('lib/features/settings/settings_page.dart').readAsStringSync(),
      contains('更新假期表时联网'),
    );
  });

  test('关于页（v1.5.0）：备份入口改名、不再提「分享此课表」，放假 / 调休说一键套用', () {
    final about = File('lib/features/settings/about_page.dart')
        .readAsStringSync();
    expect(about, contains('「设置 → 备份与恢复」'));
    expect(about, contains('放假 / 调休：导入课表后会按学校校历提示一键套用；'));
    expect(about, contains('也可以在「设置 → 学期设置」里手动改。'));
    for (final gone in <String>[
      '分享此课表',
      '「设置 → 导出备份」',
      '套用节假日安排',
      'USE_EXACT_ALARM',
      'WebView',
      'JSON',
    ]) {
      expect(about, isNot(contains(gone)), reason: '关于页还有「$gone」');
    }
  });
}
