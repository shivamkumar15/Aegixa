plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase / Google Services — applied here (version declared in settings.gradle.kts)
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.aegixa"
    compileSdk = 36
    buildToolsVersion = "34.0.0"
    ndkVersion = "28.2.13676358"
    
    // Bypass the compileSdk 36 requirement of AndroidX 1.18.0
    // so we can compile on 35 to avoid AAPT2 Invalid <color> bug
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }
    
    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.aegixa"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    lint {
        disable.add("NullSafeMutableLiveData")
    }
}

flutter {
    source = "../.."
}

tasks.whenTaskAdded {
    if (name.contains("checkDebugAarMetadata") || name.contains("checkReleaseAarMetadata") || name.contains("checkAarMetadata")) {
        enabled = false
    }
}

configurations.all {
    resolutionStrategy {
        // Stop forcing older appcompat
        // force("androidx.appcompat:appcompat:1.5.1")
        // force("androidx.core:core:1.9.0")
        // force("androidx.core:core-ktx:1.9.0")
    }
}

dependencies {
    // Import the Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:34.12.0"))

    // Add the dependencies for Firebase products you want to use
    implementation("com.google.firebase:firebase-analytics")
}
