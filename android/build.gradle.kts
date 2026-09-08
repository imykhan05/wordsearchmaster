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

// applovin_max 4.6.4's OWN android/build.gradle hardcodes
// `compileSdkVersion 31` unconditionally — independent of this app's own
// compileSdk (36, android/app/build.gradle.kts) and unaffected by bumping
// that. Modern androidx transitives it pulls in (fragment 1.7.1,
// lifecycle 2.7.0, core-ktx 1.13.1, …) require compileSdk 34+, so AGP's
// AAR-metadata check fails the build outright — every clean checkout on a
// current Flutter/AGP toolchain hits this, not just one machine. pub.dev
// has no newer applovin_max release that fixes it (checked: 4.6.4 is still
// latest), so the module's own compileSdk is overridden here instead,
// AFTER its build.gradle has already configured the extension — a later
// assignment in `afterEvaluate` wins over the module's own DSL block.
// Scoped to this one module by name, not every subproject, so a plugin
// that already declares its compileSdk correctly is never second-guessed.
subprojects {
    if (project.name == "applovin_max") {
        afterEvaluate {
            extensions.findByType<com.android.build.gradle.LibraryExtension>()
                ?.compileSdk = 36
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
