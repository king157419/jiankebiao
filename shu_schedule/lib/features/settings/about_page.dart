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
            '本应用没有广告，也没有任何后端服务器，不需要注册账号。',
            '课表、作息、主题设置都只保存在这台手机的应用目录里，不会上传。',
            '卸载应用会一并删除这些数据，重要课表建议用「设置 → 导出备份」留一份。',
            '详细说明见「设置 → 隐私说明」。',
          ]),
          const SizedBox(height: 20),
          _section(theme, '怎么从教务系统导入', <String>[
            '1. 在课表页右上角菜单里点「从教务导入」，选择你的学校。',
            '2. 在打开的教务网页里用你自己的账号登录（可能需要短信 / 扫码验证）。',
            '3. 登录成功后点底部的「一键导入」，应用会读取当前学期课表。',
            '4. 在预览页确认学期、开学日期和课程，再选择覆盖当前课表或新建一张。',
            '登录过程完全在手机本地的网页里完成，应用不会保存你的密码。',
            '导不进来：可以请同学「分享此课表」发给你，或手动录入（支持「保存并继续添加」「复制到其他星期」）。',
          ]),
          const SizedBox(height: 20),
          _section(theme, '常见问题', <String>[
            '导入后周次不对：到「设置 → 学期设置」改开学日期，它必须是第 1 周的周一。',
            '上课时间和学校不一样：到「设置 → 作息时间」逐节调整，或一键恢复默认作息。',
            '放假 / 调休：到「设置 → 学期设置 → 调休 / 停课」按日期设置。',
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
