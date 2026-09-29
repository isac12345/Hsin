plugins {
  alias(libs.plugins.android.application)
  alias(libs.plugins.kotlin.android)
  alias(libs.plugins.compose.compiler)
}

android {
  namespace = "com.hsin"
  compileSdk = 34

  defaultConfig {
    applicationId = "com.hsin"
    minSdk = 26
    targetSdk = 34
    versionCode = 1
    versionName = "1.0.0-beta"
  }

  buildTypes {
    debug {
      isDebuggable = true
    }
    release {
      isMinifyEnabled = false
      proguardFiles(
        getDefaultProguardFile("proguard-android-optimize.txt"),
        "proguard-rules.pro"
      )
      // signingConfigs deliberately omitted (debug default only; release signed later)
    }
  }

  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }

  kotlinOptions {
    jvmTarget = "17"
  }

  buildFeatures {
    compose = true
  }

  // Compiler Compose dikelola plugin org.jetbrains.kotlin.plugin.compose
  // (versi = versi Kotlin, sesuai panduan migrasi resmi); blok
  // composeOptions sengaja tidak dipakai agar tidak ganda.

  packaging {
    resources {
      excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
  }
}

dependencies {
  implementation(platform(libs.compose.bom))
  implementation(libs.compose.ui)
  implementation(libs.compose.foundation)
  implementation(libs.compose.ui.graphics)
  implementation(libs.compose.ui.tooling.preview)
  implementation(libs.activity.compose)
  implementation(libs.lifecycle.viewmodel.compose)
  implementation(libs.lifecycle.runtime.ktx)
  implementation(libs.coroutines.android)
  implementation(libs.compose.material3)
}
