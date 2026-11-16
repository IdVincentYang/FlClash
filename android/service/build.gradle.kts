import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.gradle.api.tasks.testing.Test

plugins {
    id("com.android.library")
}

android {
    namespace = "com.follow.clash.service"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        // Unit tests live under android/tests/ instead of each module's src/test.
        getByName("test").java.setSrcDirs(listOf("../tests/service"))
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":core"))
    implementation(project(":common"))
    implementation(libs.gson)
    implementation(libs.androidx.core)
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}

tasks.register<JavaExec>("generateUidPackageIdentityFixture") {
    group = "verification"
    description = "Generate the cross-language UID identity fixture using the production resolver"
    dependsOn("compileDebugUnitTestKotlin")
    // Regeneration needs compiled tests, not golden assertions against the previous fixture.
    classpath = tasks.getByName<Test>("testDebugUnitTest").classpath
    mainClass.set("com.follow.clash.service.UidPackageIdentityFixture")
    args(providers.gradleProperty("uidIdentityFixtureOutput").getOrElse(
        rootProject.file("../core/testdata/uid_package_identity.json").absolutePath,
    ))
}
