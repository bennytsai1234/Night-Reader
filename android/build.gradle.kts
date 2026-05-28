allprojects {
    repositories {
        google()
        mavenCentral()
    }
    configurations.all {
        resolutionStrategy {
            // home_widget uses "glance-appwidget:1.+" which resolves to alpha versions
            // requiring AGP 9.1.0+ and compileSdk 37. Pin to the latest stable.
            force("androidx.glance:glance-appwidget:1.1.1")
            force("androidx.glance:glance-preview:1.1.1")
        }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    afterEvaluate {
        val android = project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        android?.apply {
            // 強制將所有子專案（插件）升級至 SDK 36，避免低版本插件在 SDK 36 環境下出現 android.* 包找不到的問題
            compileSdkVersion(36)

            // 自動修復缺失的 namespace
            if (namespace == null) {
                namespace = "io.legado.reader.${project.name.replace("-", ".")}"
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

gradle.projectsEvaluated {
    allprojects {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = "17"
            targetCompatibility = "17"
            // 添加此行以靜音過時方法的警告
            options.compilerArgs.add("-Xlint:-deprecation")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
