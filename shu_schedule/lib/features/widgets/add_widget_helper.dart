import 'package:flutter/material.dart';

import '../../core/app_brand.dart';
import '../../core/native_bridge.dart';

/// 「把桌面小组件加到桌面」的统一入口。
///
/// 设置页的「添加桌面小组件」和长按 App 图标的 `add_widget` 快捷方式都走这里。
///
/// 先试系统弹窗（Android 8.0+ 且启动器支持 `requestPinAppWidget`）；
/// 弹不出来（老系统、老启动器、异常）就退回去显示手动添加的步骤。
Future<void> requestAddWidget(
  BuildContext context, {
  NativeBridge? bridge,
}) async {
  final ok = await (bridge ?? NativeBridge.instance).requestPinWidget();
  if (ok) return; // 系统确认框已经弹出来了，剩下的交给用户。
  if (!context.mounted) return;
  await showManualAddWidgetGuide(context);
}

/// 手动把小组件拖到桌面的图文步骤（启动器不支持系统弹窗时的降级路径）。
Future<void> showManualAddWidgetGuide(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('手动添加小组件'),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('你的桌面不支持直接弹确认框，按下面的步骤加一次就好：'),
            SizedBox(height: 12),
            Text('1. 回到桌面，长按桌面空白处；'),
            Text('2. 点「小组件」（部分手机叫「原子组件」「应用挂件」「桌面工具」）；'),
            Text('3. 在列表里找到「${AppBrand.name}」；'),
            Text('4. 长按它的预览图，拖到桌面空位松手。'),
            SizedBox(height: 12),
            Text(
              '小提示：放上去之后可以长按小组件把它往下拉高，'
              '课越多显示得越多；装不下时列表本身也能上下滑动。',
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}
