plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("maven-publish")
}

android {
    namespace  = "com.bleforemulator"
    compileSdk = 34

    defaultConfig {
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

publishing {
    publications {
        register<MavenPublication>("release") {
            groupId    = "com.github.yourhandle"   // JitPack replaces this automatically
            artifactId = "BLEForEmulator"
            version    = "0.1.0"

            afterEvaluate {
                from(components["release"])
            }
        }
    }
}

// No extra dependencies — sockets via java.net, JSON via org.json (built into Android)
