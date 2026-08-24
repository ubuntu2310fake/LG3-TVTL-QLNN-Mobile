import java.io.FileInputStream
import java.util.Properties

// --- ĐỌC CẤU HÌNH CHỮ KÝ SỐ TỪ GITHUB HOẶC LOCAL ---
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.lg3.quan_ly_nen_nep"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        
        // Bật tính năng Desugaring (Cú pháp KTS)
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }
    // =======================================================

    // TẠO CHỮ KÝ RELEASE DỰA TRÊN FILE KEY.PROPERTIES
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    defaultConfig {
        applicationId = "com.lg3.quan_ly_nen_nep"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // ÉP ỨNG DỤNG DÙNG CHỮ KÝ CHÍNH THỨC KHI XUẤT BẢN
            signingConfig = signingConfigs.getByName("release")
            
            // KHÔNG ĐƯỢC PHÉP CHO R8 LÀM RỐI CODE
            isMinifyEnabled = false
            isShrinkResources = false
            
            // BẢO VỆ CODE KHỎI R8
            //proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")
        }
    }
    
    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
}

flutter {
    source = "../.."
}

// Thêm thư viện hỗ trợ dịch Java 8 (Cú pháp KTS)
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}