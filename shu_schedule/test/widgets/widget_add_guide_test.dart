import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/features/widgets/widget_add_guide.dart';

/// v1.5.0 D4：「手动添加小组件」按 `Build.MANUFACTURER` / `BRAND` 选步骤。
void main() {
  group('guideBrandOf', () {
    // (manufacturer, brand) → 期望。值取自各家真机常见的 Build 字段。
    final cases = <(String?, String?, WidgetGuideBrand)>[
      ('Xiaomi', 'Xiaomi', WidgetGuideBrand.xiaomi),
      ('Xiaomi', 'Redmi', WidgetGuideBrand.xiaomi),
      ('Xiaomi', 'POCO', WidgetGuideBrand.xiaomi),
      (null, 'redmi', WidgetGuideBrand.xiaomi),
      ('HUAWEI', 'HUAWEI', WidgetGuideBrand.huawei),
      ('HONOR', 'HONOR', WidgetGuideBrand.huawei),
      ('HUAWEI', 'HONOR', WidgetGuideBrand.huawei),
      ('OPPO', 'OPPO', WidgetGuideBrand.oppo),
      ('OnePlus', 'OnePlus', WidgetGuideBrand.oppo),
      ('realme', 'realme', WidgetGuideBrand.oppo),
      ('vivo', 'vivo', WidgetGuideBrand.vivo),
      ('vivo', 'iQOO', WidgetGuideBrand.vivo),
      ('samsung', 'samsung', WidgetGuideBrand.samsung),
      ('SAMSUNG', 'Galaxy', WidgetGuideBrand.samsung),
      // 模拟器（AVD）和 Pixel。
      ('Google', 'google', WidgetGuideBrand.other),
      ('unknown', 'generic', WidgetGuideBrand.other),
      ('Meizu', 'meizu', WidgetGuideBrand.other),
      // 拿不到。
      (null, null, WidgetGuideBrand.other),
      ('', '', WidgetGuideBrand.other),
      // 大小写混写。
      ('xIaOmI', null, WidgetGuideBrand.xiaomi),
      (null, 'IqOo', WidgetGuideBrand.vivo),
      ('oNePlUs', null, WidgetGuideBrand.oppo),
    ];
    for (final (manufacturer, brand, expected) in cases) {
      test('$manufacturer / $brand → ${expected.name}', () {
        expect(
          guideBrandOf(manufacturer: manufacturer, brand: brand),
          expected,
        );
      });
    }
  });

  test('guideBrandOfDevice：直接吃 deviceInfo 的 Map，字段类型不对就忽略', () {
    expect(
      guideBrandOfDevice(<String, Object?>{
        'manufacturer': 'vivo',
        'brand': 'iQOO',
        'sdkInt': 35,
      }),
      WidgetGuideBrand.vivo,
    );
    expect(
      guideBrandOfDevice(<String, Object?>{'brand': 'HONOR'}),
      WidgetGuideBrand.huawei,
    );
    expect(
      guideBrandOfDevice(const <String, Object?>{}),
      WidgetGuideBrand.other,
    );
    expect(
      guideBrandOfDevice(<String, Object?>{'manufacturer': 42, 'brand': null}),
      WidgetGuideBrand.other,
    );
  });

  group('步骤文案', () {
    test('每个品牌正好一套，3–4 步，最后两步是「找到简课表」和「拖到桌面」', () {
      expect(
        widgetGuides.map((g) => g.brand).toSet(),
        WidgetGuideBrand.values.toSet(),
      );
      expect(widgetGuides, hasLength(WidgetGuideBrand.values.length));
      for (final g in widgetGuides) {
        expect(g.steps.length, inInclusiveRange(3, 4), reason: g.title);
        expect(g.steps[g.steps.length - 2], widgetGuideFindStep);
        expect(g.steps.last, widgetGuideDragStep);
      }
    });

    test('启动器列表里的名字：4×2 叫「简课表」，2×1 叫「下一节课」', () {
      expect(widgetGuideFindStep, contains('4×2 在列表里就叫「简课表」'));
      expect(widgetGuideFindStep, contains('2×1 叫「下一节课」'));
    });

    test('各品牌的入口说法（PLAN-1.5 任务 C 第 3 条）', () {
      String all(WidgetGuideBrand b) => widgetGuideFor(b).steps.join('\n');
      expect(
        widgetGuideFor(WidgetGuideBrand.xiaomi).title,
        contains('HyperOS'),
      );
      expect(all(WidgetGuideBrand.xiaomi), contains('长按空白处'));
      expect(all(WidgetGuideBrand.xiaomi), contains('「小部件」'));
      expect(all(WidgetGuideBrand.huawei), contains('捏合'));
      expect(all(WidgetGuideBrand.huawei), contains('「窗口小工具」'));
      expect(all(WidgetGuideBrand.huawei), contains('「服务卡片」'));
      expect(all(WidgetGuideBrand.oppo), contains('「小组件」'));
      expect(all(WidgetGuideBrand.vivo), contains('「原子组件」'));
      expect(all(WidgetGuideBrand.samsung), contains('「小组件」'));
      expect(all(WidgetGuideBrand.other), contains('长按空白处'));
    });

    test('widgetGuidesFor：这台手机的那一套排第一，其余按原顺序', () {
      final order = widgetGuidesFor(WidgetGuideBrand.vivo)
          .map((g) => g.brand)
          .toList();
      expect(order, <WidgetGuideBrand>[
        WidgetGuideBrand.vivo,
        WidgetGuideBrand.xiaomi,
        WidgetGuideBrand.huawei,
        WidgetGuideBrand.oppo,
        WidgetGuideBrand.samsung,
        WidgetGuideBrand.other,
      ]);
      expect(
        widgetGuidesFor(WidgetGuideBrand.other).first.brand,
        WidgetGuideBrand.other,
      );
      expect(widgetGuidesFor(WidgetGuideBrand.xiaomi), hasLength(6));
    });
  });
}
