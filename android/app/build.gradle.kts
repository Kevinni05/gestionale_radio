import java.util.Properties
import java.io.File

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeys = Properties()
val privateReleaseKeyFile = File(System.getProperty("user.home"), ".radiotech/signing/key.properties")
val releaseKeyFile = System.getenv("ANDROID_KEY_PROPERTIES_PATH")?.let { file(it) }
    ?: rootProject.file("key.properties").takeIf { it.exists() } ?: privateReleaseKeyFile
if (releaseKeyFile.exists()) releaseKeyFile.inputStream().use { releaseKeys.load(it) }
fun releaseKey(name: String, env: String): String? = System.getenv(env) ?: releaseKeys.getProperty(name)
val releaseStore = releaseKey("storeFile", "ANDROID_KEYSTORE_PATH")

gradle.taskGraph.whenReady {
    if (allTasks.any { it.name == "assembleRelease" || it.name == "bundleRelease" }) {
        require(!releaseStore.isNullOrBlank() && file(releaseStore!!).isFile) {
            "Production builds require the existing configured keystore; unsigned releases are forbidden."
        }
    }
}

android {
    namespace = "com.example.gestionale_radio"
    compileSdk = 36

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.gestionale_radio"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
