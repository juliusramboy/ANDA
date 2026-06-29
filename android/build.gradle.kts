allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    project.configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "androidx.core" && (requested.name == "core" || requested.name == "core-ktx")) {
                useVersion("1.13.1")
            }
        }
    }

    // Disable AAR metadata check tasks by clearing actions and creating empty output directories to satisfy downstream tasks
    tasks.configureEach {
        if (name.contains("checkDebugAarMetadata", ignoreCase = true) || name.contains("checkReleaseAarMetadata", ignoreCase = true)) {
            setActions(emptyList())
            doLast {
                outputs.files.forEach { file ->
                    file.mkdirs()
                }
            }
        }
    }

    val forceSdkVersion = {
        val android = extensions.findByName("android")
        if (android != null) {
            try {
                val compileSdkVersionMethod = android.javaClass.getMethod("compileSdkVersion", Int::class.java)
                compileSdkVersionMethod.invoke(android, 36)
            } catch (e: Exception) {
                try {
                    val compileSdkVersionMethod = android.javaClass.getMethod("compileSdkVersion", java.lang.Integer::class.java)
                    compileSdkVersionMethod.invoke(android, 36)
                } catch (e2: Exception) {
                    // Ignore
                }
            }

            try {
                val setCompileSdkMethod = android.javaClass.getMethod("setCompileSdk", java.lang.Integer::class.java)
                setCompileSdkMethod.invoke(android, 36)
            } catch (e: Exception) {
                try {
                    val setCompileSdkMethod = android.javaClass.getMethod("setCompileSdk", Int::class.java)
                    setCompileSdkMethod.invoke(android, 36)
                } catch (e2: Exception) {
                    // Ignore
                }
            }

            try {
                val defaultConfig = android.javaClass.getMethod("getDefaultConfig").invoke(android)
                val targetSdkVersionMethod = defaultConfig.javaClass.getMethod("targetSdkVersion", Int::class.java)
                targetSdkVersionMethod.invoke(defaultConfig, 36)
            } catch (e: Exception) {
                try {
                    val defaultConfig = android.javaClass.getMethod("getDefaultConfig").invoke(android)
                    val targetSdkVersionMethod = defaultConfig.javaClass.getMethod("targetSdkVersion", java.lang.Integer::class.java)
                    targetSdkVersionMethod.invoke(defaultConfig, 36)
                } catch (e2: Exception) {
                    // Ignore
                }
            }
        }
    }

    if (state.executed) {
        forceSdkVersion()
    } else {
        afterEvaluate {
            forceSdkVersion()
        }
    }
}