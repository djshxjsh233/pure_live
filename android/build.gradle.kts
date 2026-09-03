import com.android.build.gradle.BaseExtension
import java.util.Properties
import java.io.File

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// --- 核心修改：直接从 pubspec.yaml 解析 versionCode ---
val pubspecVersionCode: String by lazy {
    try {
        val pubspecFile = rootProject.file("../pubspec.yaml")
        if (pubspecFile.exists()) {
            val versionLine = pubspecFile.readLines().find { it.trim().startsWith("version:") }
            versionLine?.substringAfterLast("+")?.trim() ?: "1"
        } else {
            "1"
        }
    } catch (e: Exception) {
        "1"
    }
}

// 依然保留 local.properties 加载（用于其他 Flutter 路径配置）
val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// AGP 9 兼容补丁：第三方插件(如 floating) 未声明 compileSdk, AGP9 强校验——统一补全
subprojects {
    afterEvaluate {
         if (project.name != "app") {
            extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
                defaultConfig.minSdk = 23 
                compileSdkVersion(37) // AGP9 补全第三方插件缺失的 compileSdk
                if (namespace.isNullOrBlank()) {
                    namespace = project.group.toString()
                }
            }
        }
        tasks.matching { it.name.contains("process", ignoreCase = true) && it.name.contains("Manifest") }.configureEach {
            doLast {
                val targetVersionCode = pubspecVersionCode
                
                outputs.files.forEach { outputDir ->
                    if (outputDir.exists()) {
                        outputDir.walkTopDown().forEach { file ->
                            if (file.name == "AndroidManifest.xml") {
                                try {
                                    val content = file.readText(Charsets.UTF_8)
                                    val pattern = "android:versionCode=\"\\d+\""
                                    val regex = pattern.toRegex()

                                    if (regex.containsMatchIn(content)) {
                                        val replacement = "android:versionCode=\"$targetVersionCode\""
                                        val updatedContent = content.replace(regex, replacement)
                                        file.writeText(updatedContent, Charsets.UTF_8)
                                        println(">>> [PUBSPEC_SYNC] Found: ${file.absolutePath} -> Fixed to $targetVersionCode")
                                    }
                                } catch (e: Exception) { }
                            }
                        }
                    }
                }
            }
        }
    }
}

subprojects {
    if (project.name != "app") {
        evaluationDependsOn(":app")
    }
}

// 统一 Java 编译版本(消除第三方模块 source/target 8 obsolete 警告)
// afterEvaluate 覆盖第三方显式 sourceCompatibility=8; Gradle9 对已评估项目
// 直接 afterEvaluate 会崩 → state.executed 分支兜底
subprojects {
    val forceJava17 = {
        tasks.withType(org.gradle.api.tasks.compile.JavaCompile::class.java).configureEach {
            options.release.set(17)
        }
    }
    if (state.executed) forceJava17() else afterEvaluate { forceJava17() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
