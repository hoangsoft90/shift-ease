# =============================================================================
# ShiftEase — R8 / ProGuard rules for release builds (2026-09-12)
# =============================================================================
# Why this file exists: `flutter build apk --release` runs R8 with minification
# ON (the Flutter Gradle plugin sets `releaseBuildType.isMinifyEnabled = true`),
# while debug builds are not minified. That asymmetry means a release-only crash
# can be completely invisible during development — which is exactly what
# happened here.
#
# THE BUG (reproduced on a real device — Pixel 3a, Android 12, release APK):
#
#   java.lang.RuntimeException: Unable to get provider
#       androidx.startup.InitializationProvider:
#     java.lang.RuntimeException: Failed to create an instance of
#       androidx.work.impl.WorkDatabase
#     at androidx.work.WorkManagerInitializer.b(...)
#
# The app has no WorkManager code of its own. WorkManager + Room arrive as
# transitive dependencies of the ads SDK (`play-services-ads` -> androidx.work
# -> room-runtime) and WorkManager auto-initializes through `androidx.startup`,
# i.e. in a ContentProvider, BEFORE Application.onCreate() — so the process dies
# on every cold start and no Dart error handling can ever run.
#
# Room does not call the generated implementation directly. It builds the class
# NAME at runtime and loads it reflectively:
#
#   Class.forName("androidx.work.impl.WorkDatabase_Impl").newInstance()
#
# Room's own consumer rule (`-keep class * extends androidx.room.RoomDatabase`)
# preserves the class and its name, so `Class.forName` succeeds — but it does not
# preserve the no-arg constructor. R8's shrinking step sees no *static* caller
# for `<init>()`, removes it, and `newInstance()` then throws
# InstantiationException, which Room reports as the message above.
#
# (Ref: Room release notes 2.7.0-beta01 ship this rule in the consumer proguard
# file; square/leakcanary documents the same crash on a minified app.)
#
# THE FIX: keep the class, its name, AND its no-arg constructor. The wildcard
# covers every Room-generated implementation in any transitive dependency, not
# just today's `WorkDatabase_Impl`. Cost is a handful of unshrunk classes;
# without it the app cannot launch at all.
-keep class * extends androidx.room.RoomDatabase { <init>(); }

# Belt and braces: name the class we actually hit so the intent survives even if
# a future Room version changes its own consumer rules.
-keepclassmembers class androidx.work.impl.WorkDatabase_Impl {
    <init>();
}
