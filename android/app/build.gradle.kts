import groovy.json.JsonSlurper
import java.util.Base64
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

// This opt-in build is only for local Find N2 TRACE runs: it keeps the Release
// signer while compiling Flutter in Debug mode, so kDebugMode TRACE controls are
// available without changing the installed package signature or app data.
// Never enable it in CI; the signing key must remain local and untracked.
val localDebugUsesReleaseSigning =
    providers.gradleProperty("localDebugUsesReleaseSigning").orNull == "true"
val runningInCi =
    providers.environmentVariable("CI").orNull.equals("true", ignoreCase = true) ||
        providers.environmentVariable("GITHUB_ACTIONS").orNull.equals("true", ignoreCase = true)

if (localDebugUsesReleaseSigning && runningInCi) {
    throw GradleException(
        "localDebugUsesReleaseSigning is local-only and is forbidden in CI."
    )
}

if (releaseTaskRequested || localDebugUsesReleaseSigning) {
    val signingBuildLabel = if (releaseTaskRequested) "Release" else "local Debug with Release signing"
    if (!releaseKeyPropertiesFile.isFile) {
        val missingKeyMessage = if (releaseTaskRequested) {
            "Release signing is required. Configure android/key.properties with the existing signing key before building."
        } else {
            "Local Debug with Release signing is required. Configure android/key.properties with the existing local signing key before building."
        }
        throw GradleException(missingKeyMessage)
    }
    val requiredSigningFields = listOf("storePassword", "keyPassword", "keyAlias")
    val missingSigningFields = requiredSigningFields.filter {
        releaseSigningProperties.getProperty(it)?.isNotBlank() != true
    }
    if (releaseStoreFilePath.isBlank() || missingSigningFields.isNotEmpty()) {
        throw GradleException(
            "$signingBuildLabel signing configuration is incomplete. Check storeFile, storePassword, keyAlias and keyPassword in android/key.properties."
        )
    }
    if (releaseKeystoreFile?.isFile != true) {
        throw GradleException(
            "$signingBuildLabel keystore configured in android/key.properties was not found."
        )
    }

    if (releaseTaskRequested) {
        // The issuer public keys are public configuration, but must enter the
        // exact Release Dart build as a Dart define. Never put issuer private
        // material in this JSON or in the Android application.
        val encodedDefines = providers.gradleProperty("dart-defines").orNull.orEmpty()
        val ringDefines = encodedDefines.split(",")
            .filter { it.isNotBlank() }
            .mapNotNull { encoded ->
                runCatching {
                    String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
                }.getOrNull()
            }
            .filter { it.startsWith("YANJI_LICENSE_KEY_RING=") }

        if (ringDefines.size != 1) {
            throw GradleException(
                "Release production license trust anchor is required. " +
                    "Pass exactly one --dart-define=YANJI_LICENSE_KEY_RING=<public-key-json>."
            )
        }

        fun rejectReleaseKeyRing(reason: String): Nothing =
            throw GradleException("Release production license Key Ring is invalid: $reason")

        val keyRingJson = ringDefines.single().substringAfter("=")
        val root = runCatching { JsonSlurper().parseText(keyRingJson) }.getOrNull()
            as? Map<*, *> ?: rejectReleaseKeyRing("expected a JSON object")
        if (root.keys != setOf("keys")) {
            rejectReleaseKeyRing("only the keys property is allowed")
        }
        val issuerEntries = root["keys"] as? List<*>
            ?: rejectReleaseKeyRing("keys must be an array")
        if (issuerEntries.isEmpty()) {
            rejectReleaseKeyRing("at least one production issuer public key is required")
        }

        val seenIssuerIds = mutableSetOf<String>()
        var hasIssuingTrustAnchor = false
        // This public key and issuer ID come only from the test-vector fixture.
        // Reject all encodings here so a Release Key Ring cannot trust the test issuer.
        val testIssuerId = "test-issuer-01"
        val testPublicKeyBase64Url = "A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg"
        val testPublicKeyHex = "03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8"

        issuerEntries.forEach { rawEntry ->
            val entry = rawEntry as? Map<*, *>
                ?: rejectReleaseKeyRing("each issuer entry must be an object")
            if (entry.keys != setOf("key_id", "public_key_base64url", "status")) {
                rejectReleaseKeyRing("issuer entries may contain only key_id, public_key_base64url and status")
            }
            val keyId = entry["key_id"] as? String
                ?: rejectReleaseKeyRing("issuer key_id must be a string")
            val encodedPublicKey = entry["public_key_base64url"] as? String
                ?: rejectReleaseKeyRing("issuer public key must be a Base64URL string")
            val status = entry["status"] as? String
                ?: rejectReleaseKeyRing("issuer status must be a string")
            if (!Regex("^[a-z0-9][a-z0-9._-]{0,63}$").matches(keyId)) {
                rejectReleaseKeyRing("issuer key_id has an invalid format")
            }
            if (!seenIssuerIds.add(keyId)) {
                rejectReleaseKeyRing("duplicate issuer key_id: $keyId")
            }
            if (keyId == testIssuerId || keyId.startsWith("test-", ignoreCase = true)) {
                rejectReleaseKeyRing("test issuer IDs are forbidden")
            }
            if (!Regex("^[A-Za-z0-9_-]{43}$").matches(encodedPublicKey)) {
                rejectReleaseKeyRing("Ed25519 public key must be an unpadded 32-byte Base64URL value")
            }
            val publicKeyBytes = runCatching {
                Base64.getUrlDecoder().decode(encodedPublicKey)
            }.getOrNull() ?: rejectReleaseKeyRing("issuer public key encoding is invalid")
            if (publicKeyBytes.size != 32) {
                rejectReleaseKeyRing("Ed25519 public key must decode to exactly 32 bytes")
            }
            val publicKeyHex = publicKeyBytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }
            if (encodedPublicKey == testPublicKeyBase64Url ||
                publicKeyHex == testPublicKeyHex) {
                rejectReleaseKeyRing("the protocol test-vector public key is forbidden")
            }
            if (status !in setOf("active", "standby", "retired", "revoked", "compromised")) {
                rejectReleaseKeyRing("issuer status is unknown")
            }
            if (status == "active" || status == "standby") {
                hasIssuingTrustAnchor = true
            }
        }
        if (!hasIssuingTrustAnchor) {
            rejectReleaseKeyRing("at least one active or standby production issuer is required")
        }
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
        debug {
            // Explicit opt-in for local TRACE runs only. Default Debug builds
            // continue using the standard Android Debug signing identity.
            if (localDebugUsesReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
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
