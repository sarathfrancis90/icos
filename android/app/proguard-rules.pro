# Icos R8/ProGuard keep rules.
# Applied to release builds only (see android/app/build.gradle.kts).
# Flutter plugins ship their own consumer rules; these cover the gaps.

# --- Flutter engine & embedding -------------------------------------------
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# Flutter's deferred-components / Play Core references (not used, but referenced
# by the engine) — silence missing-class warnings.
-dontwarn com.google.android.play.core.**

# --- Firebase (core, analytics, crashlytics, messaging) -------------------
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Crashlytics: keep file/line info for readable stack traces.
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
-keep class com.google.firebase.crashlytics.** { *; }
-dontwarn com.google.firebase.crashlytics.**

# --- Supabase / OkHttp / OkIO (used by supabase_flutter via Ktor / OkHttp) --
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# --- Kotlin ---------------------------------------------------------------
-keep class kotlin.Metadata { *; }
-keepclassmembers class **$WhenMappings { <fields>; }
-keepclassmembers class kotlin.Metadata { public <methods>; }
-dontwarn kotlin.**
-dontwarn kotlinx.**

# --- Annotations & reflection metadata ------------------------------------
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses,EnclosingMethod
-keepattributes RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations
-keepattributes Exceptions

# --- Hive (pure Dart; no JVM reflection) — nothing to keep. ----------------

# --- Google Sign-In / Credential Manager ---------------------------------
-keep class com.google.android.libraries.identity.googleid.** { *; }
-dontwarn com.google.android.libraries.identity.googleid.**
-keep class androidx.credentials.** { *; }
-dontwarn androidx.credentials.**

# --- flutter_local_notifications (uses Gson reflection for scheduled notifs) --
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes *Annotation*
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-dontwarn com.google.gson.**

# --- App code -------------------------------------------------------------
-keep class com.icos.game.** { *; }

# --- Misc -----------------------------------------------------------------
# javax.* referenced by some transitive libs on older SDKs.
-dontwarn javax.annotation.**
-dontwarn org.slf4j.**
