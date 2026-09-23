# 上大课表 —— PowerShell 环境变量
# 用法： . D:\desk\claudex\12\env.ps1 ; flutter doctor -v
#
# 注意：D:\ 盘根目录对当前用户只读（Everyone = ReadAndExecute），
# 无法创建 D:\sdk，因此所有 SDK 实际落在 D:\desk\sdk\ 下。

$env:SDK_ROOT = "D:\desk\sdk"

$env:FLUTTER_ROOT      = "$env:SDK_ROOT\flutter"
$env:ANDROID_SDK_ROOT  = "$env:SDK_ROOT\android"
$env:ANDROID_HOME      = $env:ANDROID_SDK_ROOT
$env:ANDROID_USER_HOME = "$env:SDK_ROOT\android_user"
$env:ANDROID_AVD_HOME  = "$env:SDK_ROOT\android_user\avd"
$env:GRADLE_USER_HOME  = "$env:SDK_ROOT\gradle"
$env:PUB_CACHE         = "$env:SDK_ROOT\pub_cache"
$env:JAVA_HOME         = "D:\MCLDownload\ext\jre-v64-220420\jdk17"

if (-not $env:HTTP_PROXY)  { $env:HTTP_PROXY  = "http://127.0.0.1:7897" }
if (-not $env:HTTPS_PROXY) { $env:HTTPS_PROXY = "http://127.0.0.1:7897" }
if (-not $env:NO_PROXY)    { $env:NO_PROXY    = "localhost,127.0.0.1" }

$env:PATH = "$env:FLUTTER_ROOT\bin;$env:JAVA_HOME\bin;$env:ANDROID_SDK_ROOT\cmdline-tools\latest\bin;$env:ANDROID_SDK_ROOT\platform-tools;$env:ANDROID_SDK_ROOT\emulator;$env:PATH"

$env:PROJECT_DIR = "D:\desk\claudex\12\shu_schedule"
