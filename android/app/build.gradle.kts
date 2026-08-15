import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release imza bilgileri REPO DIŞINDA tutulur: android/key.properties git
// tarafından yok sayılır, keystore ise ev dizinindedir. Bu dosya yalnız
// anahtar ADLARINI bilir; hiçbir değer kaynak koda girmez.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

/** Release imzası için gerekli alanların tamamı dolu mu. */
val hasReleaseSigning =
    keystorePropertiesFile.exists() &&
        listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
            .all { !keystoreProperties.getProperty(it).isNullOrBlank() }

// Fail-fast: yalnız RELEASE görevleri çalışırken. Yapılandırma zamanında
// patlatmak, key.properties'i olmayan geliştiricinin debug build'ini de
// kırardı. Mesaj bilinçli olarak GENELDİR — parola ya da dosya içeriği
// hata metnine girmez.
gradle.taskGraph.whenReady {
    val releaseTaskNames = listOf("bundleRelease", "assembleRelease", "packageRelease", "signRelease")
    val needsReleaseSigning = allTasks.any { task ->
        releaseTaskNames.any { task.name.startsWith(it) }
    }
    if (needsReleaseSigning && !hasReleaseSigning) {
        throw GradleException(
            "Release imzası yapılandırılmamış. android/key.properties bulunamadı " +
                "ya da storeFile / storePassword / keyAlias / keyPassword " +
                "alanlarından biri eksik. Şablon: android/key.properties.example",
        )
    }
}

android {
    namespace = "com.kararveriyorum.karar_veriyorum"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications (≥ v10) core library desugaring gerektirir.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.kararveriyorum.karar_veriyorum"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Alanlar yalnız key.properties dolu olduğunda bağlanır; eksikse
            // yukarıdaki taskGraph kontrolü açık bir mesajla durdurur.
            if (hasReleaseSigning) {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Debug anahtarıyla imzalama KALDIRILDI (PR: release/android-signing).
            // Debug imzalı AAB Play tarafından reddedilir; ayrıca App Check
            // Play Integrity release parmak izine bağlıdır.
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
