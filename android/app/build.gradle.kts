import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// CI builds only the arm64 artifact used by the Find N2 acceptance target.
// Local and release builds keep all configured ABI splits.
val ciArm64Only = providers.gradleProperty("ciArm64Only").orNull == "true"

// A signed Release must use the original local signing identity. Never fall back to the Debug key.
val releaseKeyPropertiesFile = rootProject.file("key.properties")
val releaseSigningProperties = Properties()
if (releaseKeyPropertiesFile.isFile) {
    releaseKeyPropertiesFile.inputStream().use { input ->
        releaseSigningProperties.load(input)
    }
}
val releaseStoreFilePath = releaseSigningProperties.getProperty("storeFile")?.trim().orEmpty()
val releaseKeystoreFile = releaseStoreFilePath
    .takeIf { it.isNotEmpty() }
    ?.let { file(it) }
val releaseTaskRequested = gradle.startParameter.taskNames.any { requestedTask ->
    requestedTask.substringAfterLast(":").contains("release", ignoreCase = true)
}
if (releaseTaskRequested) {
    if (!releaseKeyPropertiesFile.isFile) {
        throw GradleException(
            "Release signing is required. Configure android/key.properties with the existing signing key before building."
        )
    }
    val requiredSigningFields = listOf("storePassword", "keyPassword", "keyAlias")
    val missingSigningFields = requiredSigningFields.filter {
        releaseSigningProperties.getProperty(it)?.isNotBlank() != true
    }
    if (releaseStoreFilePath.isBlank() || missingSigningFields.isNotEmpty()) {
        throw GradleException(
            "Release signing configuration is incomplete. Check storeFile, storePassword, keyAlias and keyPassword in android/key.properties."
        )
    }
    if (releaseKeystoreFile?.isFile != true) {
        throw GradleException(
            "Release signing keystore file configured in android/key.properties was not found."
        )
    }
}

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
            keyAlias = releaseSigningProperties.getProperty("keyAlias")
            keyPassword = releaseSigningProperties.getProperty("keyPassword")
            storeFile = releaseKeystoreFile
            storePassword = releaseSigningProperties.getProperty("storePassword")
            // The existing release key is PKCS12 even when its file uses a .jks suffix.
            storeType = releaseSigningProperties.getProperty("storeType")
                ?.takeIf { it.isNotBlank() } ?: "PKCS12"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // ABI splits remain available for local builds. CI uses one ordinary arm64 Debug APK.
    splits {
        abi {
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
