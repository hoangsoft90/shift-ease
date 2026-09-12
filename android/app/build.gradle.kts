import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Ads master switch (2026-09-11)
// ---------------------------------------------------------------------------
// Read from a Gradle project property so CI can strip ads WITHOUT touching Dart:
//   flutter build apk --release --android-project-arg=enableAds=false
// (that flag is translated by flutter_tools into `-PenableAds=false`).
// When false the AdMob APPLICATION_ID meta-data is blanked in the merged
// manifest — the SDK has no app ID to initialize with and never requests an ad.
// The Dart side is gated independently (AppAdsConfig.enableAds, fed by
// `--dart-define=ENABLE_ADS=...`), so both halves must be flipped together;
// the release workflow passes both flags.
// Ads are ON unless the property is explicitly the string "false" (unset or
// unrecognised values keep ads on — the safe default for a monetised app).
// NOTE: this once read `...equals("false")`, which assigned `true` exactly when
// ads were being disabled, so `-PenableAds=false` shipped the production app id
// and builds without the flag shipped none. Keep the polarity explicit.
val enableAds: Boolean =
    (((findProperty("enableAds") as? String) ?: "true").trim().lowercase() != "false")

// Real AdMob Android application ID (AdMob console, 2026-09-11). Only a
// manifest placeholder — WHICH ad unit serves is decided at runtime by
// AppAdsConfig (testAds → Google's official test units).
val adsAppId: String =
    if (enableAds) "ca-app-pub-6917313063209470~6379119743" else ""

// ---------------------------------------------------------------------------
// Release signing — keystore never lives in the repo
// ---------------------------------------------------------------------------
// CI decodes the keystore from GitHub secrets and writes android/key.properties;
// locally the file is gitignored (android/.gitignore covers key.properties,
// *.keystore, *.jks). When it is absent, release builds fall back to the debug
// signing config so `flutter build apk --release` still produces an installable
// APK (debug-signed — fine for QA, NOT uploadable to Play).
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKeystore) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
// storeFile in key.properties is resolved relative to android/ (rootProject).
val releaseStoreFile: File? =
    keystoreProperties.getProperty("storeFile")?.let { rootProject.file(it) }

android {
    namespace = "com.shiftease.shiftease"
    // Pinned (2026-09-11): Google Play requires targetSdk 36 for updates from
    // 2026-08-31. compileSdk must be >= targetSdk, so both are pinned to 36
    // instead of tracking flutter.* (which can lag). Verified against the
    // flutter-android-build proven matrix (AGP 9.1.0 / Gradle 9.3.1).
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (Java 8+ APIs on older Android).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.shiftease.shiftease"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // google_mobile_ads 9.x requires minSdk 24 (plugin build.gradle);
        // pinned explicitly so a future flutter.minSdkVersion regression
        // cannot break the manifest merge.
        minSdk = 24
        // Play Store requirement from 2026-08-31 (see compileSdk note above).
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Only declared when a keystore is actually available — a half-filled
        // release config would break every build on machines without secrets.
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storePassword = keystoreProperties.getProperty("storePassword")
                storeFile = releaseStoreFile
            }
        }
    }

    buildTypes {
        release {
            // Release-signed when android/key.properties exists (CI secrets or a
            // local keystore); otherwise debug-signed so QA builds still work.
            signingConfig =
                if (hasReleaseKeystore) signingConfigs.getByName("release")
                else signingConfigs.getByName("debug")
            manifestPlaceholders["adsAppId"] = adsAppId
        }
        debug {
            manifestPlaceholders["adsAppId"] = adsAppId
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
