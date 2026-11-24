/// 隐私说明的位置与更新日期。
///
/// 正文在 `assets/privacy.md`（设置 → 隐私说明），只做展示：v1.5.0 起不再有
/// 首次启动的同意框，也不再记录「同意过哪一版」，改正文只需要同步 [updatedAt]。
/// v1.5.0 正文换成给学生看的白话短文（PLAN-1.5 第 3 节）；完整的权限、依赖、
/// 联网地址清单在根 README。
class PrivacyPolicy {
  PrivacyPolicy._();

  /// 正文更新日期（和 privacy.md 末尾保持一致）。
  static const String updatedAt = '2026-10-08';

  /// 正文 asset 路径。
  static const String assetPath = 'assets/privacy.md';
}
