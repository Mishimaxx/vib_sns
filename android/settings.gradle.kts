import org.gradle.api.Project
import org.gradle.kotlin.dsl.closureOf

pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.7.0" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.3.15") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "1.8.22" apply false
}

include(":app")

// Some third-party plugins (for example flutter_blue_plus on older versions)
// still expect the legacy `flutter` Gradle extension that the Groovy templates
// used to create. When using the Kotlin DSL templates this extension does not
// exist, so we provide equivalent values here before any project is evaluated.
val legacyFlutterConfig = mapOf(
    "compileSdkVersion" to 35,
    "minSdkVersion" to 21,
    "targetSdkVersion" to 35
)
gradle.beforeProject(
    closureOf<Project> {
        if (name != "app") {
            extensions.extraProperties["flutter"] = legacyFlutterConfig
        }
    },
)
