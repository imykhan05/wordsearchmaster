plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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

    buildTypes {
        release {
            // TODO(P24): switch to the upload keystore signing config once
            // android/key.properties exists. Debug-signed for now so every
            // flavor is runnable before release engineering (Wave 5).
            signingConfig = signingConfigs.getByName("debug")
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
