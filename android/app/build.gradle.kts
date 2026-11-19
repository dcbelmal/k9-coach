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
    // Wersja release jest podpisywana WYŁĄCZNIE tym kluczem – bez niego budowa
    // kończy się błędem (nigdy nie podpisujemy release kluczem debug).
    // Klucza NIE ma w repozytorium. CI odtwarza go z sekretu KEYSTORE_BASE64
    // do katalogu tymczasowego i podaje ścieżkę:
    //   KEYSTORE_PATH     – ścieżka do pliku .p12 (poza repozytorium),
    //   KEYSTORE_PASSWORD – hasło (sekret GitHub),
    //   KEY_ALIAS         – opcjonalnie, domyślnie "valkor".
    val keystorePassword = System.getenv("KEYSTORE_PASSWORD")
    val keystorePath = System.getenv("KEYSTORE_PATH")?.takeIf { it.isNotBlank() }
    val keystoreFile = keystorePath?.let { file(it) }
    val signingProblem = when {
        keystorePath == null -> "brak zmiennej KEYSTORE_PATH (ścieżka do pliku klucza .p12)"
        keystoreFile?.isFile != true -> "plik klucza nie istnieje: $keystorePath"
        keystorePassword.isNullOrEmpty() -> "brak hasła KEYSTORE_PASSWORD"
        else -> null
    }
    val releaseSigningReady = signingProblem == null
    signingConfigs {
        if (releaseSigningReady) {
            create("valkor") {
                storeFile = keystoreFile!!
                storeType = "PKCS12"
                storePassword = keystorePassword
                keyAlias = System.getenv("KEY_ALIAS")?.takeIf { it.isNotBlank() } ?: "valkor"
                keyPassword = keystorePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseSigningReady) signingConfigs.getByName("valkor") else null
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    // Czytelny błąd zamiast niepodpisanego albo źle podpisanego APK.
    gradle.taskGraph.whenReady {
        val wantsRelease = allTasks.any { t ->
            t.project == project && t.name.contains("Release") &&
                (t.name.startsWith("assemble") || t.name.startsWith("bundle") || t.name.startsWith("package"))
        }
        if (wantsRelease && !releaseSigningReady) {
            throw GradleException(
                "Nie można podpisać wersji release: $signingProblem. " +
                    "Ustaw KEYSTORE_PATH i KEYSTORE_PASSWORD (w CI: sekrety KEYSTORE_BASE64 i KEYSTORE_PASSWORD) " +
                    "albo zbuduj wersję testową: flutter build apk --debug. " +
                    "Release nigdy nie jest podpisywany kluczem debug, bo taki APK nie zainstaluje się na poprzednią wersję."
            )
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
