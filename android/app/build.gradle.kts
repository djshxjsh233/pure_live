import java.util.Properties // 添加Properties类的导入

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // 移除 kotlin-android: AGP 9.0+ 内建 Kotlin(builtInKotlin=true), 显式声明会冲突
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 加载local.properties文件
val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use { stream ->
            load(stream) // 现在可以正确识别load方法
        }
    }
}

// 加载签名配置
val keystoreProperties = Properties().apply { // 同样添加了导入
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { stream ->
            load(stream) // 现在可以正确识别load方法
        }
    }
}

android {
    namespace = "com.mystyle.purelive"
    compileSdk = 37 // Android 17 (依赖file_picker/intent_plus等已要求compileSdk37)
    ndkVersion = flutter.ndkVersion
    lint {
        disable.add("NullSafeMutableLiveData")
        checkReleaseBuilds = false
        abortOnError = false
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.mystyle.purelive"
        minSdk = flutter.minSdkVersion 
        multiDexEnabled = true 
        targetSdk = 37 // 面向 Android 17
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"].toString()
            keyPassword = keystoreProperties["keyPassword"].toString()
            storeFile = file(keystoreProperties["storeFile"].toString())
            storePassword = keystoreProperties["storePassword"].toString()
            // v1(JAR)/v2/v3 全签名：老设备/国产系统直接安装需 v1, 密钥轮换兼容需 v3
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
        }
    }

    buildTypes {
       release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                  getDefaultProguardFile("proguard-android-optimize.txt"),
                  file("proguard-rules.pro")
              )
        }
       debug {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}    
