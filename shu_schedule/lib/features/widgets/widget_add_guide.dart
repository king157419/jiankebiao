import '../../core/app_brand.dart';

/// 「手动添加小组件」按手机品牌分的几套步骤（v1.5.0，D4）。
///
/// 纯数据 + 纯函数，不依赖 Flutter，方便单测。面板（`add_widget_helper.dart`）
/// 用 [guideBrandOf] 决定默认展开哪一套，其它的折叠着、点开可看。
enum WidgetGuideBrand { xiaomi, huawei, oppo, vivo, samsung, other }

/// 按 `android.os.Build` 的 `MANUFACTURER` / `BRAND` 判断该给哪一套步骤。
///
/// 两个字段转小写后做包含匹配（子品牌和母公司的桌面是同一套）：
/// xiaomi / redmi / poco → 小米；huawei / honor → 华为；oppo / oneplus / realme → OPPO；
/// vivo / iqoo → vivo；samsung → 三星；其余（包括模拟器的 Google、拿不到时的空值）→ 其他。
WidgetGuideBrand guideBrandOf({String? manufacturer, String? brand}) {
  final s = '${manufacturer ?? ''} ${brand ?? ''}'.toLowerCase();
  bool any(List<String> keys) => keys.any(s.contains);
  if (any(const <String>['xiaomi', 'redmi', 'poco'])) {
    return WidgetGuideBrand.xiaomi;
  }
  if (any(const <String>['huawei', 'honor'])) return WidgetGuideBrand.huawei;
  if (any(const <String>['oppo', 'oneplus', 'realme'])) {
    return WidgetGuideBrand.oppo;
  }
  if (any(const <String>['vivo', 'iqoo'])) return WidgetGuideBrand.vivo;
  if (s.contains('samsung')) return WidgetGuideBrand.samsung;
  return WidgetGuideBrand.other;
}

/// [guideBrandOf] 的便捷版：直接吃 `NativeBridge.deviceInfo()` 的结果。
WidgetGuideBrand guideBrandOfDevice(Map<String, Object?> device) {
  final manufacturer = device['manufacturer'];
  final brand = device['brand'];
  return guideBrandOf(
    manufacturer: manufacturer is String ? manufacturer : null,
    brand: brand is String ? brand : null,
  );
}

/// 每套步骤最后都一样的两步：在列表里认出是哪个，再拖到桌面。
///
/// 4×2 在启动器列表里的名字就是 App 名（`widget_day_label = @string/app_name`），
/// 2×1 叫「下一节课」（`widget_next_label`）。
const String widgetGuideFindStep =
    '找到「${AppBrand.name}」：4×2 在列表里就叫「${AppBrand.name}」，2×1 叫「下一节课」';

/// 最后一步。
const String widgetGuideDragStep = '按住预览图拖到桌面空位，松手就好';

/// 某个品牌的标题和步骤。
class WidgetGuide {
  final WidgetGuideBrand brand;
  final String title;
  final List<String> steps;

  const WidgetGuide(this.brand, this.title, this.steps);
}

/// 六套步骤，顺序就是面板里的默认顺序（面板会把这台手机的那一套挪到最前）。
const List<WidgetGuide> widgetGuides = <WidgetGuide>[
  WidgetGuide(WidgetGuideBrand.xiaomi, '小米 / 红米（HyperOS、MIUI）', <String>[
    '回到桌面，长按空白处',
    '点「添加小组件」（有的版本叫「小部件」）',
    widgetGuideFindStep,
    widgetGuideDragStep,
  ]),
  WidgetGuide(WidgetGuideBrand.huawei, '华为 / 荣耀', <String>[
    '回到桌面，两根手指在空白处向内捏合',
    '点「窗口小工具」（有的版本叫「服务卡片」）',
    widgetGuideFindStep,
    widgetGuideDragStep,
  ]),
  WidgetGuide(WidgetGuideBrand.oppo, 'OPPO / 一加 / realme', <String>[
    '回到桌面，长按空白处',
    '点「小组件」',
    widgetGuideFindStep,
    widgetGuideDragStep,
  ]),
  WidgetGuide(WidgetGuideBrand.vivo, 'vivo / iQOO', <String>[
    '回到桌面，长按空白处',
    '点「原子组件」或「小组件」（没看到就往下翻，找「应用挂件」）',
    widgetGuideFindStep,
    widgetGuideDragStep,
  ]),
  WidgetGuide(WidgetGuideBrand.samsung, '三星', <String>[
    '回到桌面，长按空白处',
    '点「小组件」',
    widgetGuideFindStep,
    widgetGuideDragStep,
  ]),
  WidgetGuide(WidgetGuideBrand.other, '其他手机', <String>[
    '回到桌面，长按空白处',
    '点「小组件」（有的手机叫「窗口小工具」或「桌面工具」）',
    widgetGuideFindStep,
    widgetGuideDragStep,
  ]),
];

/// [brand] 对应的那一套。
WidgetGuide widgetGuideFor(WidgetGuideBrand brand) =>
    widgetGuides.firstWhere((g) => g.brand == brand);

/// 面板里的顺序：这台手机的那一套放最前，其余保持 [widgetGuides] 的顺序。
List<WidgetGuide> widgetGuidesFor(WidgetGuideBrand current) => <WidgetGuide>[
  widgetGuideFor(current),
  for (final g in widgetGuides)
    if (g.brand != current) g,
];
