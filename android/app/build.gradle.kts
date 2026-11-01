plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// CI builds only the arm64 artifact used by the Find N2 acceptance target.
// Local and release builds keep all configured ABI splits.
val ciArm64Only = providers.gradleProperty("ciArm64Only").orNull == "true"

android {
    namespace = "com.nihaisha.nihaisha_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.nihaisha.nihaisha_app"
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // The CI artifact is a single arm64 APK, not an ABI-split APK.
        // Flutter's default ABI injection is disabled by the CI Gradle property.
        if (ciArm64Only) {
            ndk {
                abiFilters.clear()
                abiFilters.add("arm64-v8a")
            }
        }
    }

    signingConfigs {
        create("release") {
            // 从 key.properties 读取签名配置
            val keyPropertiesFile = rootProject.file("key.properties")
            if (keyPropertiesFile.exists()) {
                val map = mutableMapOf<String, String>()
                keyPropertiesFile.readLines().forEach { line ->
                    val trimmed = line.trim()
                    if (trimmed.isNotEmpty() && !trimmed.startsWith("#") && trimmed.contains("=")) {
                        val parts = trimmed.split("=", limit = 2)
                        map[parts[0].trim()] = parts[1].trim()
                    }
                }
                keyAlias = map["keyAlias"]
                keyPassword = map["keyPassword"]
                storeFile = file(map["storeFile"] ?: "")
                storePassword = map["storePassword"]
                // canonical keystore 是 openssl 生成的 PKCS12（.jks 后缀），必须显式 storeType 否则 Gradle 按默认 jks 解析失败
                storeType = map["storeType"] ?: "PKCS12"
            }
        }
    }

    buildTypes {
        release {
            // 如果key.properties存在则用release签名，否则fallback到debug签名
            val keyPropertiesFile = rootProject.file("key.properties")
            signingConfig = if (keyPropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // 生产构建：开启 R8 混淆 + 资源收缩（瘦身 + 符号混淆）
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // ABI 分包：生成 armeabi-v7a / arm64-v8a / x86_64 独立 APK + 通用包，
    // 单架构 APK 体积约减半（原 52MB 通用包），便于 GitHub 直发与 Play 上架。
    splits {
        abi {
            // CI uses one ordinary arm64 APK so Flutter can discover app-debug.apk.
            // Local and release builds retain the three ABI splits plus universal APK.
            isEnable = !ciArm64Only
            if (!ciArm64Only) {
                reset()
                include("armeabi-v7a", "arm64-v8a", "x86_64")
                isUniversalApk = true
            }
        }
    }
}

dependencies {
    implementation("com.google.ai.edge.litertlm:litertlm-android:0.18.0")
    testImplementation("junit:junit:4.13.2")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
