import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// release 签名信息放在 android/key.properties（不进版本控制）。
// 见 https://docs.flutter.dev/deployment/android#signing-the-app
// 文件缺失时自动回退到 debug 签名，保证别人 clone 下来也能构建。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "cn.shu.schedule"
    // compileSdk 必须 >= 36：webview_flutter_android 与 androidx.core 1.18.0
    // 都要求依赖方 compile against API 36，用 35 会直接 BUILD FAILED。
    // targetSdk 仍按 PLAN §1 固定在 35（运行时行为不变）。
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // v1.4.0：flutter_local_notifications 依赖 java.time 等 Java 8+ API 做定时通知，
        // 插件 README 要求宿主开启 core library desugaring（即使不用定时也要开）。
        // minSdk 24 原生支持多 dex，不需要 multiDexEnabled。
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "cn.shu.schedule"
        // PLAN §1：minSdk 24 / targetSdk 35 / compileSdk 35。
        minSdk = 24
        targetSdk = 35
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 版本与 flutter_local_notifications 22.3.1 README / 插件自身 build.gradle 一致。
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // v1.4.0 C：小组件「显示哪一天 / 头部状态 / 下一节 / 重绘时刻」这些纯逻辑的 JVM 单测
    // （src/test/kotlin，不需要模拟器）：`gradlew :app:testDebugUnitTest`。
    testImplementation("junit:junit:4.13.2")
}
