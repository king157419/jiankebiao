import 'dart:async';

import 'package:shu_schedule/core/holiday_presets.dart';
import 'package:shu_schedule/core/holiday_repository.dart';
import 'package:shu_schedule/core/repo_config.dart';
import 'package:shu_schedule/core/update/update_checker.dart';

/// 一次 [FakeHolidayRepository.refresh] 调用的参数。
class FakeRefreshCall {
  final bool force;
  final UpdateInfo? manifest;

  const FakeRefreshCall({required this.force, this.manifest});
}

/// 不碰网络、不碰磁盘的假日表仓库（v1.4.0 测试用）。
///
/// [load] 返回 [data]；[refresh] 记录参数、按 [onRefresh] 给结果（默认 unchanged），
/// 结果是 updated 且给了 [afterUpdate] 时，之后的 [load] 返回 [afterUpdate]。
class FakeHolidayRepository extends HolidayRepository {
  FakeHolidayRepository({
    required this.data,
    this.afterUpdate,
    this.onRefresh,
    super.repo = const RepoConfig(githubOwner: 'me', githubRepo: 'jkb'),
  });

  HolidayPresets data;
  final HolidayPresets? afterUpdate;
  final HolidayRefreshResult Function(FakeRefreshCall call)? onRefresh;

  final List<FakeRefreshCall> calls = <FakeRefreshCall>[];
  int loads = 0;

  @override
  Future<HolidayPresets> load() async {
    loads++;
    return data;
  }

  @override
  Future<HolidayRefreshResult> refresh({
    bool force = false,
    DateTime? now,
    DateTime? lastRefresh,
    FutureOr<void> Function(DateTime time)? onSuccess,
    UpdateInfo? manifest,
  }) async {
    final previous = data;
    final call = FakeRefreshCall(force: force, manifest: manifest);
    calls.add(call);
    var result =
        onRefresh?.call(call) ??
        HolidayRefreshResult(
          HolidayRefreshStatus.unchanged,
          presets: data,
          previousPresets: previous,
        );
    if (result.isUpdated && result.previousPresets == null) {
      result = HolidayRefreshResult(
        result.status,
        presets: result.presets,
        previousPresets: previous,
        source: result.source,
        errors: result.errors,
      );
    }
    final next = afterUpdate;
    if (result.isUpdated && next != null) data = next;
    return result;
  }
}
