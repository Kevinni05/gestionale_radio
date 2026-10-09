import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeys = Properties()
val releaseKeyFile = rootProject.file("key.properties")
if (releaseKeyFile.exists()) releaseKeyFile.inputStream().use { releaseKeys.load(it) }
fun releaseKey(name: String, env: String): String? = System.getenv(env) ?: releaseKeys.getProperty(name)
val releaseStore = releaseKey("storeFile", "ANDROID_KEYSTORE_PATH")
val buyerApplicationId = System.getenv("ANDROID_APPLICATION_ID")
    ?.trim()
    ?.takeIf { it.isNotEmpty() }
    ?: "com.example.gestionale_radio"
val buyerAppName = System.getenv("ANDROID_APP_NAME")
    ?.trim()
    ?.takeIf { it.isNotEmpty() }
    ?: "RadioTech"

android {
    namespace = "com.example.gestionale_radio"
    compileSdk = 36

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = buyerApplicationId
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = buyerAppName
    }

    signingConfigs {
        if (!releaseStore.isNullOrBlank()) {
            create("release") {
                storeFile = file(releaseStore)
                storePassword = releaseKey("storePassword", "ANDROID_KEYSTORE_PASSWORD")
                keyAlias = releaseKey("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = releaseKey("keyPassword", "ANDROID_KEY_PASSWORD")
                require(!storePassword.isNullOrBlank() && !keyAlias.isNullOrBlank() && !keyPassword.isNullOrBlank()) {
                    "Release signing requires all four keystore properties or ANDROID_KEY* environment variables."
                }
            }
        }
    }
    buildTypes {
        release {
            if (!releaseStore.isNullOrBlank()) signingConfig = signingConfigs.getByName("release")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

// Questo singolo blocco moderno sostituisce tutta la vecchia configurazione Java e Kotlin
kotlin {
    jvmToolchain(17)
}

flutter {
    source = "../.."
}
