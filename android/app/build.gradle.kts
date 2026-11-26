import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release credentials stay outside source control. Environment variables also
// support a CI secret store without generating a credentials file in the repo.
val signingProperties = Properties()
val signingPropertiesPath = providers.environmentVariable("WATERDISTRICT_ANDROID_SIGNING_PROPERTIES").orNull
val signingPropertiesFile = if (signingPropertiesPath != null) file(signingPropertiesPath) else rootProject.file("key.properties")
if (signingPropertiesFile.exists()) signingPropertiesFile.inputStream().use { signingProperties.load(it) }
fun signingValue(environment: String, property: String): String? =
    providers.environmentVariable(environment).orNull ?: signingProperties.getProperty(property)

val releaseStore = signingValue("WATERDISTRICT_ANDROID_KEYSTORE", "storeFile")
val releaseStorePassword = signingValue("WATERDISTRICT_ANDROID_STORE_PASSWORD", "storePassword")
val releaseAlias = signingValue("WATERDISTRICT_ANDROID_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("WATERDISTRICT_ANDROID_KEY_PASSWORD", "keyPassword")
if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }) {
    require(listOf(releaseStore, releaseStorePassword, releaseAlias, releaseKeyPassword).all { !it.isNullOrBlank() }) {
        "Release signing is required. Run scripts/build-android-release.ps1 or configure the Android signing environment variables."
    }
}

android {
    namespace = "ph.maramag.waterdistrictconnect"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ph.maramag.waterdistrictconnect"
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
        create("release") {
            storeFile = releaseStore?.let { file(it) }
            storePassword = releaseStorePassword
            keyAlias = releaseAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
