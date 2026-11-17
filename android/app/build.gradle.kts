plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "pl.k9coach.app"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "pl.k9coach.app"
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

    // Stały klucz podpisu: każda nowa wersja instaluje się na poprzednią bez utraty danych.
    // Hasło jest w sekrecie GitHub KEYSTORE_PASSWORD (zmienna środowiskowa przy budowie).
    val keystorePassword = System.getenv("KEYSTORE_PASSWORD")
    signingConfigs {
        if (!keystorePassword.isNullOrEmpty()) {
            create("valkor") {
                storeFile = file("valkor-release.p12")
                storeType = "PKCS12"
                storePassword = keystorePassword
                keyAlias = "valkor"
                keyPassword = keystorePassword
            }
        }
    }

    buildTypes {
        release {
            // Bez hasła (np. lokalnie) podpisujemy kluczem debug, jak wcześniej.
            signingConfig = if (!keystorePassword.isNullOrEmpty()) signingConfigs.getByName("valkor")
                else signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
