import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (git-ignored) must define
//   storeFile, storePassword, keyAlias, keyPassword
// See docs/RELEASE_RUNBOOK.md for how to create the upload keystore.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Escape hatch for local smoke-testing a release build without the upload key.
// Never set this in CI: a debug-signed AAB is rejected by Google Play.
val allowDebugSigning = System.getenv("ALLOW_DEBUG_SIGNING") == "true"

android {
    namespace = "com.icos.game"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (java.time on API < 26).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.icos.game"
        // Android 6.0 (Marshmallow). Required by firebase_messaging / google_sign_in
        // and gives us runtime permissions + modern TLS. Do not rely on the Flutter
        // default here; it changes between Flutter releases.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use the upload keystore when present. Otherwise fall back to the debug
            // keystore so that configuration still succeeds for debug builds; the
            // guard below fails any *release* build loudly unless explicitly allowed.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // R8 code shrinking + resource shrinking. Keep rules live in proguard-rules.pro.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

// Fail loudly when a release variant is built without the upload keystore.
// Hooked on preReleaseBuild so debug/profile builds are unaffected.
tasks.configureEach {
    if (name == "preReleaseBuild") {
        doFirst {
            if (!hasReleaseKeystore) {
                if (allowDebugSigning) {
                    logger.warn(
                        "WARNING: android/key.properties not found. Signing the RELEASE build " +
                            "with the DEBUG keystore because ALLOW_DEBUG_SIGNING=true. " +
                            "This artifact cannot be uploaded to Google Play."
                    )
                } else {
                    throw GradleException(
                        """
                        |Release signing is not configured: android/key.properties was not found.
                        |
                        |To build a store-ready release:
                        |  1. Create the upload keystore (see docs/RELEASE_RUNBOOK.md, "Google Play" section).
                        |  2. Create android/key.properties with storeFile, storePassword, keyAlias, keyPassword.
                        |
                        |To build a throw-away release for local testing only (NOT uploadable):
                        |  ALLOW_DEBUG_SIGNING=true flutter build apk --release
                        """.trimMargin()
                    )
                }
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
