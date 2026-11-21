import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties
import java.util.Base64

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use { load(it) }
    }
}

val buildDefines = mutableMapOf<String, String>()
providers.gradleProperty("dart-defines").orNull?.split(",")?.filter { it.isNotEmpty() }?.forEach {
    val define = String(Base64.getDecoder().decode(it), Charsets.UTF_8)
    val split = define.indexOf('=')
    if (split <= 0 || buildDefines.put(define.substring(0, split), define.substring(split + 1)) != null) {
        throw GradleException("Ambiguous Android build intent")
    }
}
val releaseCandidate = buildDefines["ANDROID_RELEASE_CANDIDATE"] == "true"
val baseApplicationId = buildDefines["ANDROID_PACKAGE_ID"] ?: "com.follow.clash"
val androidAppName = buildDefines["ANDROID_APP_NAME"]
val androidSystemIcon = when (buildDefines["ANDROID_SYSTEM_ICON"]) {
    null, "false" -> false
    "true" -> true
    else -> throw GradleException("Invalid ANDROID_SYSTEM_ICON; expected true or false")
}
if (!baseApplicationId.matches(Regex("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+"))) {
    throw GradleException("Invalid Android base applicationId")
}
if (androidAppName != null && (androidAppName.isBlank() || androidAppName.any {
        it.code < 32 || it.code in 127..159 || it == '\u2028' || it == '\u2029'
    })) {
    throw GradleException("Invalid Android app name")
}
if (System.getenv("FLCLASH_ANDROID_PROFILE") != null &&
    (baseApplicationId != "com.follow.clash" || androidAppName != null || androidSystemIcon)) {
    throw GradleException("The managed Android profile requires its default identity and appearance")
}
if (buildDefines.containsKey("ANDROID_RELEASE_CANDIDATE") &&
    (buildDefines["ANDROID_RELEASE_CANDIDATE"] != "true" ||
        buildDefines["APP_ENV"] !in setOf("pre", "stable") ||
        System.getenv("FLCLASH_ANDROID_PROFILE") != null || file("keystore.jks").exists())) {
    throw GradleException("Release candidates require isolated Android pre/stable without a release key")
}

val releaseStoreFile = file("keystore.jks")
val releaseStorePassword = localProperties.getProperty("storePassword")
val releaseKeyAlias = localProperties.getProperty("keyAlias")
val releaseKeyPassword = localProperties.getProperty("keyPassword")
val hasReleaseSigning = releaseStoreFile.exists() &&
    releaseStorePassword != null &&
    releaseKeyAlias != null &&
    releaseKeyPassword != null

android {
    namespace = "com.follow.clash"
    compileSdk = libs.versions.compileSdk.get().toInt()
    ndkVersion = libs.versions.ndkVersion.get()

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = baseApplicationId
        minSdk = flutter.minSdkVersion
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["androidAppIcon"] = if (androidSystemIcon) "@null" else "@mipmap/ic_launcher"
        manifestPlaceholders["androidAppBanner"] = if (androidSystemIcon) "@null" else "@mipmap/ic_banner"
        manifestPlaceholders["androidDebugLabel"] = if (androidAppName != null) "@string/app_name" else "FlClash Debug"
        if (androidAppName != null) {
            resValue("string", "app_name", "\"" + androidAppName
                .replace("\\", "\\\\").replace("\"", "\\\"").replace("'", "\\'") + "\"")
        }
    }

    buildFeatures {
        buildConfig = true
        resValues = true
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            applicationIdSuffix = ".dev"
        }

        release {
            isMinifyEnabled = true
            isShrinkResources = true
            if (releaseCandidate) {
                signingConfig = signingConfigs.getByName("debug")
            } else if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
                applicationIdSuffix = ".dev"
            }

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    sourceSets {
        // Unit tests live under android/tests/ instead of each module's src/test.
        getByName("test").java.setSrcDirs(listOf("../tests/app"))
    }

}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(project(":service"))
    implementation(project(":common"))
    implementation(project(":core"))
    implementation(libs.core.splashscreen)
    implementation(libs.gson)
    implementation(libs.smali.dexlib2) {
        exclude(group = "com.google.guava", module = "guava")
    }
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
