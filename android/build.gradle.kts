buildscript {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    dependencies {
        // AGP 9 built-in Kotlin defaults to KGP 2.2.10, while Flutter 3.47
        // requires >= 2.2.20. Keep Kotlin built into AGP and raise only its
        // runtime KGP dependency; do not re-apply kotlin-android.
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.20")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    // AGP 9 移除了舊的 com.android.build.gradle.BaseExtension 型別，改用新版公開 DSL。
    // 將所有 Android library 外掛的 compileSdk 拉齊到 37（只升不降），避免仍釘在
    // 35/36 的外掛在 API 37 app 環境下出現 android.* 解析不一致。各外掛自行維持其
    // Java/Kotlin bytecode target，這裡不再全域覆寫 jvmTarget。
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.api.dsl.LibraryExtension> {
            if ((compileSdk ?: 0) < 37) {
                compileSdk = 37
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
