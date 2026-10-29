import java.io.File
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

// -----------------------------------------------------------------------------
// Release signing.
//
// `android/key.properties` supplies storeFile, storePassword, keyAlias and
// keyPassword. It and the keystore itself are gitignored, so no credential
// reaches the repository; `key.properties.example` documents the shape.
//
// The release build type used to fall back to `signingConfigs.getByName("debug")`
// - the stock Flutter template line - which meant every release artifact was
// signed with the debug key and could not be uploaded to Google Play. Nothing
// failed; it just quietly produced an unpublishable build. So there is no
// fallback now: without a complete key.properties the release type gets no
// signing config at all, and asking for a release task fails outright.
// -----------------------------------------------------------------------------
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.isFile) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// Maps keys are intentionally resolved outside tracked source. A command-line
// Gradle property is useful for CI, an environment variable works for managed
// build agents, and local.properties is the last-resort developer machine
// configuration. Do not add a default key here.
val localPropertiesFile = rootProject.file("local.properties")
val localProperties = Properties()
if (localPropertiesFile.isFile) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}

fun configuredMapsApiKey(): String? =
    providers.gradleProperty("MAPS_API_KEY").orNull?.trim()?.takeIf(String::isNotEmpty)
        ?: providers.environmentVariable("MAPS_API_KEY").orNull?.trim()?.takeIf(String::isNotEmpty)
        ?: localProperties.getProperty("MAPS_API_KEY")?.trim()?.takeIf(String::isNotEmpty)

val mapsApiKey = configuredMapsApiKey()

fun keystoreProperty(name: String): String? =
    keystoreProperties.getProperty(name)?.trim()?.takeIf(String::isNotEmpty)

// A relative storeFile resolves against the `android` directory, so both
// `app/upload-keystore.jks` and an absolute path outside the repository work.
val releaseStoreFile: File? = keystoreProperty("storeFile")?.let { configured ->
    val candidate = File(configured)
    if (candidate.isAbsolute) candidate else rootProject.file(configured)
}

val missingSigningKeys: List<String> = buildList {
    if (releaseStoreFile == null) add("storeFile")
    if (keystoreProperty("storePassword") == null) add("storePassword")
    if (keystoreProperty("keyAlias") == null) add("keyAlias")
    if (keystoreProperty("keyPassword") == null) add("keyPassword")
}

val releaseSigningReady = missingSigningKeys.isEmpty() && releaseStoreFile?.isFile == true

// Whether this invocation actually asked for a release artifact. Checked so a
// missing keystore stops a release build without getting in the way of a debug
// run, which configures this same project.
val releaseRequested = gradle.startParameter.taskNames.any { taskName ->
    taskName.contains("release", ignoreCase = true)
}

if (releaseRequested && !releaseSigningReady) {
    val reason = when {
        !keystorePropertiesFile.isFile ->
            "android/key.properties does not exist."
        missingSigningKeys.isNotEmpty() ->
            "android/key.properties is missing: ${missingSigningKeys.joinToString(", ")}."
        else ->
            "the keystore named by storeFile was not found."
    }

    throw GradleException(
        """
        Release signing is not configured, so this build was stopped.

        $reason

        A release artifact must be signed with the upload key Google Play expects.
        Signing one with the debug key produces a build Play rejects, which is why
        there is no longer a fallback to it.

        To configure it:
          1. Confirm the expected upload certificate in the Google Play Console
             before creating or replacing any key.
          2. Put the keystore outside version control.
          3. Copy android/key.properties.example to android/key.properties and
             fill in storeFile, storePassword, keyAlias and keyPassword.

        Both key.properties and the keystore are gitignored. Never commit either.

        To run the app locally without a keystore, use a debug or profile build.
        """.trimIndent()
    )
}

if (releaseRequested && mapsApiKey == null) {
    throw GradleException(
        """
        Android Maps is not configured, so this release build was stopped.

        Set MAPS_API_KEY using one of these sources, in priority order:
          1. -PMAPS_API_KEY=... (for CI or an explicit Gradle invocation)
          2. the MAPS_API_KEY environment variable
          3. android/local.properties (for local development only)

        A release build never substitutes a fake or default Maps key.
        """.trimIndent()
    )
}

android {
    namespace = "com.hero.blockatie"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.hero.blockatie"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey.orEmpty()
    }

    signingConfigs {
        // Declared only when it can actually be filled in. An empty signing
        // config would be accepted here and fail much later, during packaging.
        if (releaseSigningReady) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = keystoreProperty("storePassword")
                keyAlias = keystoreProperty("keyAlias")
                keyPassword = keystoreProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // The release key, or none at all - never the debug key. The guard
            // above has already stopped the build if a release task was asked
            // for without a keystore, so reaching this with null means only that
            // a debug build is configuring the project.
            signingConfig = if (releaseSigningReady) {
                signingConfigs.getByName("release")
            } else {
                null
            }
        }
    }
}

flutter {
    source = "../.."
}
dependencies {
    // Core library desugaring for flutter_local_notifications
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
