# Keep Flutter, billing, and push entry points when R8 shrinks the release APK.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

-keep class com.revenuecat.purchases.** { *; }
-dontwarn com.revenuecat.purchases.**

-keep class com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**

-keep class com.onesignal.** { *; }
-dontwarn com.onesignal.**

-keepattributes SourceFile,LineNumberTable
-keepattributes *Annotation*
-dontwarn org.bouncycastle.**
