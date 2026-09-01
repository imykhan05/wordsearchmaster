import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// android/key.properties is gitignored — it holds the path to a real,
// private upload keystore (never committed) plus its passwords. Play
// Console rejects a debug-signed release outright: the default debug
// keystore is byte-for-byte identical on every Android SDK install (same
// fixed password, same fixed alias), so it carries no developer identity
// at all. Falling back to debug signing when this file is absent keeps
// `flutter build`/`flutter run --release` working for a fresh checkout
// with no keystore configured yet — that build is real and runnable, it
// is just not one Play Console will accept.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKeystore) load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.educativz.word_search_master"
    // Play Store requires targetSdk 36 (Android 16) for all new app submissions
    // and updates from 31 Aug 2026 — see Production Bible Ch14, audit #01.
    compileSdk = 36
    // Flutter-managed NDK: always matches the prebuilt libflutter.so shipped
    // with this Flutter version, so it never drifts out of ABI compatibility.
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Newer Android Gradle Plugin versions default this off; the three
    // flavors below each set app_name via resValue(), which AGP now
    // refuses to configure without this explicit opt-in ("Product Flavor
    // X contains custom resource values, but the feature is disabled").
    buildFeatures {
        resValues = true
    }

    defaultConfig {
        applicationId = "com.educativz.wordsearchmaster"
        minSdk = 24
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "environment"
    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "WSM Dev")
        }
        create("stg") {
            dimension = "environment"
            applicationIdSuffix = ".stg"
            versionNameSuffix = "-stg"
            resValue("string", "app_name", "WSM Staging")
        }
        create("prod") {
            dimension = "environment"
            resValue("string", "app_name", "Word Search Master")
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                // Resolved against rootProject (android/), matching where
                // key.properties itself lives — file() here would instead
                // resolve against this module's own dir (android/app/),
                // one level too deep for a relative storeFile path.
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (hasReleaseKeystore) "release" else "debug"
            )
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
