import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_brand.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';

// 版本号 v1.3.0 起定义在 app_brand.dart；这里 re-export，老的 import 不用改。
export '../../core/app_brand.dart' show appVersion;

/// 关于页：版本、数据与隐私、导入说明。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>().current;
    final colors = theme.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: <Widget>[
          Center(
            child: Column(
              children: <Widget>[
                Text(theme.decor.emoji, style: const TextStyle(fontSize: 48)),
                const SizedBox(height: 8),
                Text(
                  AppBrand.name,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: colors.headerText,
                    fontFamily: theme.titleFontFamily,
                  ),
                ),
                Text(
                  'v$appVersion · ${AppBrand.tagline}',
                  style: TextStyle(fontSize: 13, color: colors.onSurfaceMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _section(theme, '无广告，数据仅存本地', <String>[
            '没有广告，没有服务器，不用注册账号。',
            '课表、作息、主题设置都只存在这台手机里，不会上传。',
            '只在你从教务导入、检查更新、更新假期表时联网。',
            '检查更新和更新假期表的请求里不带课表或个人信息；'
                '从教务导入时，账号密码只提交给学校教务系统。',
            '卸载应用会一并删除这些数据，重要课表建议用「设置 → 备份与恢复」导出一份。',
            '详细说明见「设置 → 隐私说明」。',
          ]),
          const SizedBox(height: 20),
          _section(theme, '怎么从教务系统导入', <String>[
            '1. 点课表页右上角的 ⋮，选「从教务导入」，再选你的学校。',
            '2. 在打开的教务网页里用你自己的账号登录（可能需要短信 / 扫码验证）。',
            '3. 登录成功后点底部的「一键导入课表」，应用会读取当前学期课表。',
            '4. 在预览页确认学期、开学日期和课程，再选择覆盖当前课表或新建一张。',
            '登录过程完全在手机本地的网页里完成，应用不会保存你的密码。',
            '导不进来：可以手动录入（支持「保存并继续添加」「复制到其他星期」），'
                '也可以在「设置 → 反馈」里告诉开发者。',
          ]),
          const SizedBox(height: 20),
          _section(theme, '常见问题', <String>[
            '周次不对：点课表顶部的「第 N 周」→「本周不是第 N 周？点这里校正」。',
            '上课时间和学校不一样：到「设置 → 作息时间」逐节调整，或一键恢复默认作息。',
            '放假 / 调休：导入课表后会按学校校历提示一键套用；'
                '也可以在「设置 → 学期设置」里手动改。',
            '看不到某些课：实践课、线上课在教务里没有固定节次，导入时会单独提示。',
          ]),
        ],
      ),
    );
  }

  Widget _section(AppTheme theme, String title, List<String> lines) {
    final colors = theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: colors.headerText,
          ),
        ),
        const SizedBox(height: 8),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              line,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: colors.onSurfaceMuted,
              ),
            ),
          ),
      ],
    );
  }
}
