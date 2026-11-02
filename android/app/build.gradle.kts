import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.suryatejap24.snooze"
    // Pinned (not flutter.*) so a Flutter upgrade can't silently change the
    // SDK levels; raise them on purpose and re-test alarms when you do.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.suryatejap24.snooze"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Signed with the upload key only. Without key.properties the
            // build stops (below) rather than ship a debug-signed release.
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

// Checked when a release build runs, not at configuration, so debug builds
// and CI (which have no upload key) are unaffected.
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    doFirst {
        if (!keystorePropertiesFile.exists()) {
            throw GradleException(
                "Release signing is not set up: create android/key.properties " +
                    "(see README, Release). Refusing to sign with the debug key.",
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Same version as the workmanager plugin; RearmReceiver enqueues its worker.
    implementation("androidx.work:work-runtime:2.11.2")
}

flutter {
    source = "../.."
}
