# 上大课表 —— 工具链手册（Phase 1 / Agent T 产出）

本机已安装好的 Flutter + Android 工具链、环境变量用法、常用命令、以及踩过的坑。

---

## 1. 路径一览

| 用途 | 路径 |
|---|---|
| Flutter SDK | `D:\desk\sdk\flutter`（3.47.4 stable / Dart 3.13.3） |
| Android SDK | `D:\desk\sdk\android` |
| Android cmdline-tools | `D:\desk\sdk\android\cmdline-tools\latest\bin` |
| Gradle 缓存 `GRADLE_USER_HOME` | `D:\desk\sdk\gradle` |
| Pub 缓存 `PUB_CACHE` | `D:\desk\sdk\pub_cache` |
| Android 用户目录 `ANDROID_USER_HOME` | `D:\desk\sdk\android_user`（AVD 在 `…\avd`） |
| JDK 17 `JAVA_HOME` | `D:\MCLDownload\ext\jre-v64-220420\jdk17`（Temurin 17.0.2） |
| 下载的安装包 | `D:\desk\sdk\dl\`（zip 装完后已删除，只留 `releases_windows.json`） |
| Flutter 工程 | `D:\desk\claudex\12\shu_schedule` |

> **为什么不是 `D:\sdk`**：`D:\` 盘根目录的 ACL 对普通用户只有 `Everyone = ReadAndExecute`，
> 非管理员无法在根目录新建文件夹（`New-Item D:\sdk` → Access denied）。
> 所以整套 SDK 落在可写的 `D:\desk\sdk\` 下。要改回 `D:\sdk` 需要管理员权限，
> 改了之后把 `env.sh` / `env.ps1` 里的 `SDK_ROOT` 和 `_SDK_POSIX` 一起改即可。

**没有动过任何系统环境变量 / 注册表**（没用 `setx`）。所有配置都在下面两个文件里。

已经写进 Flutter 自己配置（`~/.config/flutter/settings`）的：
```
flutter config --android-sdk "D:\desk\sdk\android"
flutter config --jdk-dir "D:\MCLDownload\ext\jre-v64-220420\jdk17"
```

---

## 2. env.sh / env.ps1 用法

### Bash（Git Bash）—— 每条命令都这样开头
```bash
source /d/desk/claudex/12/env.sh && flutter doctor -v
source /d/desk/claudex/12/env.sh && cd /d/desk/claudex/12/shu_schedule && flutter test
```

### PowerShell
```powershell
. D:\desk\claudex\12\env.ps1
cd D:\desk\claudex\12\shu_schedule
flutter test
```

两个文件设置同一组变量：`FLUTTER_ROOT`、`ANDROID_SDK_ROOT`/`ANDROID_HOME`、
`ANDROID_USER_HOME`、`ANDROID_AVD_HOME`、`GRADLE_USER_HOME`、`PUB_CACHE`、`JAVA_HOME`、
代理（`HTTP_PROXY`/`HTTPS_PROXY` = `http://127.0.0.1:7897`，`NO_PROXY` = localhost），
并把 flutter/java/cmdline-tools/platform-tools/emulator 加进 `PATH`。

> **坑**：`env.sh` 里 `PATH` 必须用 POSIX 形式（`/d/desk/sdk/flutter/bin`），
> 用 `D:/…` 的话 Git Bash 会报 `flutter: command not found`。
> 但 `FLUTTER_ROOT` 等变量必须保持 `D:/…` 形式，因为它们是给 Windows 工具读的。
> `env.sh` 里已经分开处理了，不要「统一」成一种写法。

---

## 3. 常用命令

```bash
source /d/desk/claudex/12/env.sh
cd /d/desk/claudex/12/shu_schedule

# 静态检查（必须零 error）
flutter analyze

# 单元测试
flutter test
flutter test test/schedule_utils_test.dart          # 单个文件
flutter test --name "parseWeeksText"                # 按名字过滤

# 依赖
flutter pub get
flutter pub add <pkg>
flutter pub add --dev <pkg>
flutter pub outdated

# 打包
flutter build apk --debug      # 产物：build/app/outputs/flutter-apk/app-debug.apk
flutter build apk --release    # 产物：build/app/outputs/flutter-apk/app-release.apk
flutter build apk --release --split-per-abi    # 想缩小体积时用

# 清理（Gradle 抽风时先试这个）
flutter clean && flutter pub get
```

### SDK 管理
```bash
SDKM="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager.bat"
"$SDKM" --sdk_root="$ANDROID_SDK_ROOT" --list | head -50
"$SDKM" --sdk_root="$ANDROID_SDK_ROOT" "platforms;android-36"
yes | "$SDKM" --sdk_root="$ANDROID_SDK_ROOT" --licenses
```
> 必须显式带 `--sdk_root=`，否则 sdkmanager 会按自己相对路径推断，
> 有可能把包装到 `cmdline-tools\` 的上一层去。

### 模拟器（AVD）
已装 `emulator` 与 `system-images;android-35;google_apis;x86_64`（约 3.5 GB）。

```bash
source /d/desk/claudex/12/env.sh

# 创建（--device 可选 "pixel_6" / "pixel_7"；-d 列表用 avdmanager list device）
echo no | avdmanager create avd \
  -n shu_test -k "system-images;android-35;google_apis;x86_64" -d "pixel_6"

avdmanager list avd            # 看已有 AVD
emulator -list-avds

# 启动（-no-snapshot-load 保证干净启动；-gpu host 用显卡）
emulator -avd shu_test -no-snapshot-load -gpu host &

# 等设备就绪
adb wait-for-device
adb shell getprop sys.boot_completed     # 返回 1 表示开机完成

# 安装 / 卸载 / 截图
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb uninstall cn.shu.schedule
adb exec-out screencap -p > shot.png
adb logcat -s flutter                     # 看 Flutter 日志

# 直接跑到模拟器上
flutter devices
flutter run -d emulator-5554
```
AVD 数据写在 `ANDROID_AVD_HOME`（`D:\desk\sdk\android_user\avd`），不占 C 盘。
> **注意**：模拟器尚未实际启动验证过，只是把镜像和 emulator 装好了。首次启动
> 若报 WHPX 相关错误，需要在 Windows 功能里确认「虚拟机平台 / Hyper-V」已开。

---

## 4. 已装组件版本

```
Flutter 3.47.4 • channel stable • Dart 3.13.3 • DevTools 2.60.0
Android SDK Build-Tools 35.0.0 与 36.1.0
Android SDK Platform 35 与 36
Android SDK Platform-Tools r37.0.1（adb）
Android Emulator 37.1.11.0
system-images;android-35;google_apis;x86_64
JDK Temurin 17.0.2+8
cmdline-tools 来自 commandlinetools-win-15859902_latest.zip
```

`flutter doctor` 全绿（Flutter / Windows / Android toolchain / Chrome / VS / Proxy / 设备 / 网络）。

---

## 5. 踩过的坑

1. **`D:\` 根目录不可写** → SDK 只能放 `D:\desk\sdk\`。见 §1。
2. **Git Bash 的 `PATH` 要 POSIX 形式** → 见 §2 的提示。
3. **Android SDK 36 是硬需求，两处都卡**：
   - 只装 `platforms;android-35` + `build-tools;35.0.0` 时 `flutter doctor` 报
     `Flutter requires Android SDK 36 and the Android BuildTools 28.0.3`。
     → 额外装 `platforms;android-36` + `build-tools;36.1.0`。
   - `compileSdk = 35` 时 `flutter build apk --debug` **直接 BUILD FAILED**：
     `:webview_flutter_android` / `androidx.core:core:1.18.0` / `androidx.core:core-ktx:1.18.0`
     都要求 `compile against version 36 or later`。
     → `android/app/build.gradle.kts` 里 `compileSdk = 36`。
   `targetSdk = 35`、`minSdk = 24` 保持 PLAN 的值不变（写死数字，
   不用 `flutter.compileSdkVersion`）。
4. **cmdline-tools 的 zip 内部顶层就叫 `cmdline-tools`**，必须重排成
   `<sdk>/cmdline-tools/latest/bin/...`，不能直接解压。本次做法：
   先解到临时目录再 `mv .../cmdline-tools <sdk>/cmdline-tools/latest`。
5. **Flutter zip 有 1.93 GB**（不是文档里印象中的 1 GB），解压后 3.48 GB。
   下载要加 `--retry 3 -C -`，并留够 D 盘空间。
6. **本机时区是 Mountain Standard Time（有夏令时）**，不是 Asia/Shanghai。
   这直接暴露了一个真实 bug：`DateTime.add(Duration(days: n))` 跨夏令时会得到
   `2027-01-10 23:00` 而不是 `2027-01-11 00:00`。
   **所有日期运算必须用日历加减**（`DateTime(y, m, d + n)`）**或 UTC 归一化**
   （`ScheduleUtils.addDays` / `ScheduleUtils.daysBetween`），
   不要用 `add/subtract(Duration(days:))` 和 `difference().inDays`。
   `test/schedule_utils_test.dart` 里有一条专门的回归测试盯着这件事。
7. **代理**：`HTTP_PROXY`/`HTTPS_PROXY` 已在系统里，`env.sh`/`env.ps1` 兜底一次。
   Gradle 不读这两个变量，所以另外写了 `D:\desk\sdk\gradle\gradle.properties`：
   ```
   systemProp.http.proxyHost=127.0.0.1
   systemProp.http.proxyPort=7897
   systemProp.https.proxyHost=127.0.0.1
   systemProp.https.proxyPort=7897
   systemProp.http.nonProxyHosts=localhost|127.0.0.1
   ```
   同一个文件里还设了 `org.gradle.jvmargs=-Xmx2048m`。
8. **不要在本机 curl 学校域名**（`jwxt.shu.edu.cn` 会 SSL 握手失败），导入解析只能靠
   fixtures 单测，真机由用户验证。见 PLAN §0.1。
9. **包名与目录**：`applicationId` / `namespace` 都是 `cn.shu.schedule`，
   Kotlin 源码在 `android/app/src/main/kotlin/cn/shu/schedule/`。
   `flutter create --org cn.shu --project-name shu_schedule` 默认生成的是
   `cn.shu.shu_schedule`，已手动改名并移动了 `MainActivity.kt`。
10. **磁盘吃得比想象中狠**。C 盘只剩 4 GB（一个字节都没占到）；D 盘从 27 GB 掉到 14 GB：
    Flutter 解压后 3.5 GB、`system-images;android-35` 3.5 GB、Gradle 缓存 2.2 GB+、
    Android SDK 其余约 1.5 GB。安装包 zip（2.1 GB）已删。
    再紧张的话可以删 `system-images`（放弃模拟器，改用真机）回收 3.5 GB。
