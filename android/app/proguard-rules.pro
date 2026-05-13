# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Play Core (deferred components) — tidak digunakan, suppress R8 warning
-dontwarn com.google.android.play.core.**

# mobile_scanner / MLKit barcode
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# HTTP (OkHttp / Dart http)
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }

# shared_preferences
-keep class androidx.datastore.** { *; }
-keep class com.google.** { *; }

# Keep all Parcelable / Serializable models
-keepclassmembers class * implements android.os.Parcelable { *; }
-keepclassmembers class * implements java.io.Serializable { *; }
