# 上大课表 —— Bash (Git Bash) 环境变量
# 用法：source /d/desk/claudex/12/env.sh && flutter doctor -v
#
# 注意：D:\ 盘根目录对当前用户只读（Everyone = ReadAndExecute），
# 无法创建 D:\sdk，因此所有 SDK 实际落在 D:\desk\sdk\ 下。

export SDK_ROOT="D:/desk/sdk"

export FLUTTER_ROOT="$SDK_ROOT/flutter"
export ANDROID_SDK_ROOT="$SDK_ROOT/android"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export ANDROID_USER_HOME="$SDK_ROOT/android_user"
export ANDROID_AVD_HOME="$SDK_ROOT/android_user/avd"
export GRADLE_USER_HOME="$SDK_ROOT/gradle"
export PUB_CACHE="$SDK_ROOT/pub_cache"
export JAVA_HOME="D:/MCLDownload/ext/jre-v64-220420/jdk17"

# 代理（已在系统环境里，这里兜底一次）
export HTTP_PROXY="${HTTP_PROXY:-http://127.0.0.1:7897}"
export HTTPS_PROXY="${HTTPS_PROXY:-http://127.0.0.1:7897}"
export NO_PROXY="${NO_PROXY:-localhost,127.0.0.1}"

# PATH 必须用 Git Bash 的 POSIX 形式（/d/...），否则 Bash 找不到可执行文件；
# 而上面那些环境变量必须保持 Windows 形式（D:/...），因为它们是给 Windows 工具读的。
_SDK_POSIX="/d/desk/sdk"
export PATH="$_SDK_POSIX/flutter/bin:/d/MCLDownload/ext/jre-v64-220420/jdk17/bin:$_SDK_POSIX/android/cmdline-tools/latest/bin:$_SDK_POSIX/android/platform-tools:$_SDK_POSIX/android/emulator:$PATH"

export PROJECT_DIR="/d/desk/claudex/12/shu_schedule"
