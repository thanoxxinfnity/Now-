import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. The same key must sign every build: Android refuses to install an update
// ("package invalid" / "conflicts with an existing package") when the signature changes, and the
// debug key is generated fresh on every CI runner, so it changes on every build.
//
// The key comes from environment variables (GitHub Actions secrets) or, for local builds, from
// android/key.properties. Both use the same four names. Neither file nor values are ever committed.
//   KEYSTORE_FILE (path), KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signingValue(name: String): String? =
    System.getenv(name)?.takeIf { it.isNotBlank() } ?: keyProps.getProperty(name)?.takeIf { it.isNotBlank() }
val releaseStore: File? = signingValue("KEYSTORE_FILE")?.let { path ->
    val f = File(path)
    if (f.isAbsolute) f else rootProject.file(path)
}
val hasReleaseKey = releaseStore != null && releaseStore.exists() &&
    signingValue("KEYSTORE_PASSWORD") != null && signingValue("KEY_ALIAS") != null && signingValue("KEY_PASSWORD") != null

android {
    namespace = "com.mugen.mugen_ai"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mugen.mugen_ai"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = releaseStore
                storePassword = signingValue("KEYSTORE_PASSWORD")
                keyAlias = signingValue("KEY_ALIAS")
                keyPassword = signingValue("KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                // No release key configured (a fork, a first run): a debug-signed APK still installs
                // as a fresh app, but it can NOT update an app signed with another key.
                logger.warn("WARNING: no release keystore configured; signing with the DEBUG key")
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
