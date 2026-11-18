import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// This file is deliberately ignored by Git.  Copy key.properties.example to
// key.properties and fill it with the credentials for the upload keystore.
// A Play/App Gallery release must never be signed with the debug key.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val requiredSigningKeys = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
val signingValuesPresent = requiredSigningKeys.all {
    val value = keystoreProperties.getProperty(it)
    !value.isNullOrBlank() && !value.startsWith("REPLACE_WITH_")
}
val uploadKeystore = keystoreProperties.getProperty("storeFile")
    ?.takeIf { it.isNotBlank() }?.let { rootProject.file(it) }

// Validate at task execution, not configuration: debug builds and IDE sync
// must work without production credentials. No release task may bypass this.
val validateUploadCredentials = tasks.register("validateUploadCredentials") {
    doLast {
        if (!signingValuesPresent || uploadKeystore?.isFile != true) {
            throw GradleException(
                "Configure android/key.properties using key.properties.example and an existing upload keystore."
            )
        }
    }
}
tasks.configureEach {
    if (name.contains("Release")) {
        dependsOn(validateUploadCredentials)
    }
}

android {
    namespace = "uno.dentstudy"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "uno.dentstudy"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signingValuesPresent) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = uploadKeystore
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
