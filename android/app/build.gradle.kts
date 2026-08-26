import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    val localKeyProp = file("key.properties")
    if (localKeyProp.exists()) {
        keystoreProperties.load(FileInputStream(localKeyProp))
    }
}

android {
    namespace = "com.lg3.quan_ly_nen_nep"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.lg3.quan_ly_nen_nep"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keyAliasVal = keystoreProperties.getProperty("keyAlias") ?: "lg3key"
            val keyPasswordVal = keystoreProperties.getProperty("keyPassword") ?: "123456"
            val storeFileVal = keystoreProperties.getProperty("storeFile") ?: "lg3-release.jks"
            val storePasswordVal = keystoreProperties.getProperty("storePassword") ?: "123456"

            val keyFile = if (file(storeFileVal).exists()) file(storeFileVal)
                else if (file("lg3-release.jks").exists()) file("lg3-release.jks")
                else if (rootProject.file(storeFileVal).exists()) rootProject.file(storeFileVal)
                else if (rootProject.file("app/lg3-release.jks").exists()) rootProject.file("app/lg3-release.jks")
                else file(storeFileVal)

            keyAlias = keyAliasVal
            keyPassword = keyPasswordVal
            storeFile = keyFile
            storePassword = storePasswordVal
            enableV1Signing = true
            enableV2Signing = true
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
