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
        applicationId = "com.follow.clash"
        minSdk = flutter.minSdkVersion
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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

    testOptions.unitTests {
        isIncludeAndroidResources = true
        all { it.systemProperty("robolectric.dependency.repo.url", "https://repo.maven.apache.org/maven2") }
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

tasks.matching { it.name == "packageDebugUnitTestForUnitTest" }.configureEach {
    dependsOn("copyFlutterAssetsDebug")
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
    testImplementation("org.robolectric:robolectric:4.16.1")
}
