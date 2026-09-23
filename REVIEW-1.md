# 代码审查 #1（只读审查，Phase 3 集成期间产出）— 结论：REQUEST CHANGES

范围：zfsoft_adapter / web_login_page / import_preview_page / storage / app_state / schedule_utils / widget_sync。确认成立 17 条：CRITICAL 1、HIGH 3、MEDIUM 8、LOW 5。

## CRITICAL

### C1. `Storage._writeAtomic` 不是原子写；并发 save 会把 timetables.json 删掉后写不回去 → 全量数据丢失
`lib/core/storage.dart:148-155`
- `delete()` 多余且有害：`File.rename` 在 POSIX/Windows 上都能原子覆盖目标；先删后改名造出"旧文件已删、新文件未就位"的窗口，进程被杀即课表归零。
- `.tmp` 固定文件名，两次并发 save 互相踩：A 写 tmp → B 写同一 tmp → A rename → B delete 把 A 的结果删了 → B rename 抛 FileSystemException，且异常来自未 await 的 Future，UI 无提示。
- `Storage.load()` 不认 `.tmp` 残留，静默返回空列表。
- 并发路径真实存在，5 处调用没有 await：`periods_editor_page.dart:62,74`、`term_settings_page.dart:61,84`、`timetable_manage_page.dart:54`；`AppState._commit()` 本身未串行化，导入一次触发 3~4 次 commit。

修法：
```dart
// storage.dart
static Future<void> _writeQueue = Future<void>.value();
static int _tmpSeq = 0;
static Future<void> _serialized(Future<void> Function() op) {
  final next = _writeQueue.then((_) => op());
  _writeQueue = next.then((_) {}, onError: (_) {});
  return next;
}
// saveTimetables / saveSettings 都包 _serialized(() => _writeAtomic(...))
static Future<void> _writeAtomic(File file, String content) async {
  final tmp = File('${file.path}.${_tmpSeq++}.tmp');
  await tmp.writeAsString(content, flush: true);
  await tmp.rename(file.path);  // rename 本身就是原子覆盖，不要先 delete
}
```
`_loadTimetables/_loadSettings` 开头兜底：主文件不存在但有 `<name>.*.tmp` 时取最新的 rename 回来再读（写 warning）。上述 5 个调用点补 `await`。

## HIGH

### H1. 「我已登录，直接导入」在 SSO 域名（newsso）下必然失败，错误是无意义的 `Failed to fetch`
`web_login_page.dart:341-344 → :112-123`；`zfsoft_adapter.dart:583/621`。`runJavaScript` 在当前文档源执行，newsso→jwxt 是跨源带凭据请求，被 CORS 拦截。
修法：`_startImport` 开头校验 `Uri.parse(_currentUrl).host` 是否等于 `adapter.homeUrl` 的 host，不等则 `_showError('当前页面还在 $host，无法直接抓取教务数据。', suggestion: '点「回教务首页」，等页面显示出教务系统再点导入。')` 并 return。

### H2. POST 被 302 到统一身份认证时被归类为网络错误而不是「未登录」
`zfsoft_adapter.dart:621-630`：不看 `r.status`/`r.redirected`；fetch 跟随跨源 302 直接 reject，走不到 `looksLikeLogin`。
修法（JS）：
```js
}).then(function (r) {
  if (r.status === 401 || r.status === 403) { throw { __login: true }; }
  if (('redirected' in r) && r.redirected && String(r.url).indexOf(BASE) !== 0) { throw { __login: true }; }
  return r.text();
});
...
.catch(function (e) {
  if (e && e.__login) { fail('index', '__LOGIN__'); return; }
  var isNet = e && (e.name === 'TypeError' || String(e).indexOf('Failed to fetch') >= 0);
  fail('kb', isNet ? '__NETWORK__' : e);
});
```
Dart `_errorFromScript` 加 `__NETWORK__` 分支：「请求教务接口失败，可能是登录已失效或网络不通（校外需要 VPN）」。

### H3. `_onChannelMessage` 用子串 `"progress"` 判定进度消息，终态消息（含整份 kbList）里任何字段出现该串就会被丢弃，只能等 40 秒超时；且通道对任意页面开放
`web_login_page.dart:90-104`。修法：`jsonDecode(raw)`，非 Map 忽略；`decoded['progress'] == true` 才当进度；无 `ok` 键忽略；否则 complete。

## MEDIUM
- **M1** `web_login_page.dart:59-66/201-236`：`onWebResourceError` 每次都 showDialog，无去重，SSO 链路里会叠 2~3 个弹窗。加 `_errorShowing` 标志，`whenComplete` 复位。
- **M2** `zfsoft_adapter.dart:609`：`第\s*(\d+)\s*周` 首个匹配可能抓到「第1周-第18周」范围文本 → 开学日期整体偏移。优先 `当前[^0-9]{0,6}第\s*(\d+)\s*周` / `本\s*周[^0-9]{0,4}第\s*(\d+)\s*周`，再退回宽松匹配。
- **M3** `zfsoft_adapter.dart:549-554`：`Response.text()` 强制 UTF-8，若页面 GBK 则周次永远识别不到。按 content-type 含 `gb` 时用 `TextDecoder('gbk')` 解码 arrayBuffer（try/catch 回退）。
- **M4** `zfsoft_adapter.dart:545-547,609`：脚本里有字面中文，与 :516 注释/NOTES 承诺的 `\uXXXX` 不符。二选一改齐。
- **M5** `import_preview_page.dart:50`：解析出的最大周次 > totalWeeks(默认 18) 时没有提示，超出周的课导入后永不显示。在摘要卡加提示并建议把总周数改成 maxWeek。
- **M6** `storage.dart:183-186`：`importJson` 一条坏课表让整份备份失败，与 `_loadTimetables` 的"跳过单条"不一致。逐条 try/catch，写 warnings。
- **M7** `app_state.dart:201-209`：`restoreFrom` 不校验 id 唯一/非空（重复 id 使第二张课表无法编辑）、空列表时 currentTimetableId 悬空、覆盖前不备份现有数据（建议先写 `timetables.json.before-restore-<ts>`）。
- **M8** `widget_sync.dart:150` 用 `weekOf`（裁剪）而快照用 `rawWeekOf`：假期里「今日」组件空态但「本周」PNG 画出第 1/最后一周的课。改为 `isDuringTerm ? rawWeekOf : null`，`WeekGridImage` 支持 week==null 画空态。

## LOW
- **L1** `import_preview_page.dart:135-137`：build() 里给 `_mode` 赋值，挪到 `_confirm()`。
- **L2** `zfsoft_adapter.dart:369-389`：`jcs` 与 `jc` 不一致时只取先解析成功的，无 warning；建议两者都解析取跨度更大者并 warning。
- **L3** `zfsoft_adapter.dart:261-262`：合并 key 不含 `jxbmc`。
- **L4** `course.dart:113-115`、`timetable.dart:57-59`：缺 id 时用微秒时间戳，批量可撞；在 importJson/restoreFrom 统一补 uuid。
- **L5** `zfsoft_adapter.dart:46-63`：`pathMarker` 要求尾斜杠，`/jwglxt` 无尾斜杠时 isLoggedIn=false，按钮闪灰。判定改成 `path == marker 去尾斜杠 || path.contains(marker)`。

## 已确认没问题
DST 契约全仓干净；注入脚本 ES5 兼容（无箭头/let/模板串/async）；30s JS + 40s Dart 双超时与 done 重入保护；`_jsString` 转义顺序正确；colorIndex 稳定落 0..9；脏数据跳过+warning 一致；web_login_page 的 mounted 防护到位；删最后一张课表 UI 侧有防护。
