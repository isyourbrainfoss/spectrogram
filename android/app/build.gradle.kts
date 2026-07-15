import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// Prefer committed upload-key.properties (stable Obtainium updates).
// Optional override: CI secrets write android/key.properties + release.keystore.
val uploadKeystoreProperties = Properties().apply {
    val propsFile = rootProject.file("upload-key.properties")
    if (propsFile.exists()) {
        propsFile.inputStream().use { load(it) }
    }
}
val secretKeystoreProperties = Properties()
val secretKeystorePropertiesFile = rootProject.file("key.properties")
if (secretKeystorePropertiesFile.exists()) {
    secretKeystoreProperties.load(FileInputStream(secretKeystorePropertiesFile))
}

android {
    namespace = "com.isyourbrainfoss.spectrogram"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.isyourbrainfoss.spectrogram"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (uploadKeystoreProperties.isNotEmpty() &&
            uploadKeystoreProperties.getProperty("storeFile") != null) {
            create("upload") {
                keyAlias = uploadKeystoreProperties.getProperty("keyAlias")
                keyPassword = uploadKeystoreProperties.getProperty("keyPassword")
                storeFile =
                    uploadKeystoreProperties.getProperty("storeFile")?.let {
                        rootProject.file(it)
                    }
                storePassword = uploadKeystoreProperties.getProperty("storePassword")
            }
        }
        if (secretKeystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = secretKeystoreProperties["keyAlias"] as String
                keyPassword = secretKeystoreProperties["keyPassword"] as String
                storeFile = secretKeystoreProperties["storeFile"]?.let { file(it) }
                storePassword = secretKeystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Prefer secret release key when present; else stable upload keystore.
            signingConfig = when {
                secretKeystorePropertiesFile.exists() ->
                    signingConfigs.getByName("release")
                signingConfigs.findByName("upload") != null ->
                    signingConfigs.getByName("upload")
                else ->
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
