import org.gradle.api.GradleException
import org.gradle.api.tasks.Exec
import java.io.File
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Production signing is read from android/key.properties (kept out of version
// control). Release builds fail closed when that configuration is absent.
//
// A no-secret CI verification lane is available only when both CI=true and
// YORKS_CI_EPHEMERAL_SIGNING=true are set (or the equivalent Gradle property
// -PyorksCiEphemeralSigning=true). It creates a short-lived, non-debug
// certificate under build/; artifacts from that lane must never be published.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val ciEphemeralSigningRequested =
    providers.gradleProperty("yorksCiEphemeralSigning").orNull?.toBooleanStrictOrNull() == true ||
        providers.environmentVariable("YORKS_CI_EPHEMERAL_SIGNING").orNull
            ?.toBooleanStrictOrNull() == true
val runningInCi = providers.environmentVariable("CI").orNull?.let {
    it.equals("true", ignoreCase = true) || it == "1"
} == true
val ciEphemeralSigningEnabled =
    ciEphemeralSigningRequested && runningInCi && !keystorePropertiesFile.exists()

val requiredSigningProperties =
    listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
val missingSigningProperties = requiredSigningProperties.filter {
    keystoreProperties.getProperty(it).isNullOrBlank()
}
val productionKeystoreFile = keystoreProperties.getProperty("storeFile")
    ?.takeIf { it.isNotBlank() }
    ?.let { file(it) }
val productionSigningReady =
    keystorePropertiesFile.exists() &&
        missingSigningProperties.isEmpty() &&
        productionKeystoreFile?.isFile == true

val ciEphemeralAlias = "yorks-ci-ephemeral"
val ciEphemeralPassword = "ci-ephemeral-not-for-production"
val ciEphemeralKeystoreFile =
    rootProject.layout.buildDirectory.file("ci-signing/yorks-ci-ephemeral.jks")
        .get().asFile
val keytoolExecutable = File(
    System.getProperty("java.home"),
    if (System.getProperty("os.name").startsWith("Windows", ignoreCase = true)) {
        "bin/keytool.exe"
    } else {
        "bin/keytool"
    },
)

val generateCiEphemeralSigningKey = tasks.register<Exec>(
    "generateCiEphemeralSigningKey",
) {
    description = "Creates the non-production signing key used only by CI verification builds."
    onlyIf { ciEphemeralSigningEnabled && !ciEphemeralKeystoreFile.exists() }
    outputs.file(ciEphemeralKeystoreFile)
    doFirst {
        ciEphemeralKeystoreFile.parentFile.mkdirs()
    }
    commandLine(
        keytoolExecutable.absolutePath,
        "-genkeypair",
        "-keystore",
        ciEphemeralKeystoreFile.absolutePath,
        "-storepass",
        ciEphemeralPassword,
        "-alias",
        ciEphemeralAlias,
        "-keypass",
        ciEphemeralPassword,
        "-keyalg",
        "RSA",
        "-keysize",
        "2048",
        "-validity",
        "2",
        "-dname",
        "CN=Yorks CI Ephemeral, OU=CI Only, O=Yorks, C=AE",
        "-noprompt",
    )
}

val verifyReleaseSigning = tasks.register("verifyReleaseSigning") {
    description = "Fails a release build unless production or explicit CI signing is ready."
    if (ciEphemeralSigningEnabled) {
        dependsOn(generateCiEphemeralSigningKey)
    }
    doLast {
        when {
            ciEphemeralSigningRequested && !runningInCi -> throw GradleException(
                "Ephemeral release signing is CI-only. Set CI=true only in the controlled CI lane.",
            )
            ciEphemeralSigningRequested && keystorePropertiesFile.exists() ->
                throw GradleException(
                    "Choose one release-signing lane: remove YORKS_CI_EPHEMERAL_SIGNING " +
                        "when android/key.properties is present.",
                )
            ciEphemeralSigningEnabled && !ciEphemeralKeystoreFile.isFile ->
                throw GradleException("CI ephemeral signing key generation did not produce a keystore.")
            ciEphemeralSigningEnabled -> logger.warn(
                "CI EPHEMERAL SIGNING: this release artifact is for verification only and must not be published.",
            )
            !productionSigningReady -> {
                val detail = when {
                    !keystorePropertiesFile.exists() ->
                        "android/key.properties is missing"
                    missingSigningProperties.isNotEmpty() ->
                        "android/key.properties is missing: ${missingSigningProperties.joinToString()}"
                    else ->
                        "the configured release keystore does not exist: ${productionKeystoreFile?.path}"
                }
                throw GradleException(
                    "Android release signing is not configured ($detail). " +
                        "Provide the protected production keystore configuration, or use the explicit " +
                        "CI ephemeral lane for non-publishable verification builds.",
                )
            }
        }
    }
}

android {
    // Confirmed Yorks Android identity. Keep this aligned with MainActivity's
    // Kotlin package and applicationId; changing it after Play registration is
    // a separate release decision.
    namespace = "com.yorks.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Confirmed permanent Yorks application identity. A production upload
        // still requires the protected production signing configuration.
        applicationId = "com.yorks.app"
        // local_auth (biometric unlock) requires minSdk 23.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (productionSigningReady || ciEphemeralSigningEnabled) {
            create("release") {
                if (productionSigningReady) {
                    keyAlias = keystoreProperties["keyAlias"] as String?
                    keyPassword = keystoreProperties["keyPassword"] as String?
                    storeFile = productionKeystoreFile
                    storePassword = keystoreProperties["storePassword"] as String?
                } else {
                    keyAlias = ciEphemeralAlias
                    keyPassword = ciEphemeralPassword
                    storeFile = ciEphemeralKeystoreFile
                    storePassword = ciEphemeralPassword
                }
            }
        }
    }

    buildTypes {
        release {
            if (productionSigningReady || ciEphemeralSigningEnabled) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(verifyReleaseSigning)
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

// >> GIT_ALL_IN_ONE:preBuildStartApi
tasks.named("preBuild") { dependsOn(rootProject.tasks.named("startApi")) }
// << GIT_ALL_IN_ONE:preBuildStartApi
