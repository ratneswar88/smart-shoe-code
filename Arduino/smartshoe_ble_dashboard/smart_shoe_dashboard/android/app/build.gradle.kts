plugins {
    id("com.android.application")
    id("kotlin-android")
}

android {
    namespace = "com.example.smart_shoe_flutter_app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.smart_shoe_flutter_app"
        minSdk = 21
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            // debug config if needed
        }
    }

    // Keep your NDK pin here
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}
