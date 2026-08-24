# Bỏ qua cảnh báo và giữ lại code của thư viện uCrop
-dontwarn com.yalantis.ucrop.**
-keep class com.yalantis.ucrop.** { *; }
-keep interface com.yalantis.ucrop.** { *; }

# Bỏ qua cảnh báo và giữ lại thư viện okhttp3 (mà uCrop cần)
-dontwarn okhttp3.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-keep class com.arthenica.** { *; }

-dontwarn okio.**

# --- BẢO VỆ FLUTTER PLUGINS ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# --- BẢO VỆ FIREBASE ---
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# --- BẢO VỆ FIREBASE MESSAGING (PUSH NOTIFICATION) ---
-keep class com.google.firebase.messaging.** { *; }

# --- FIX LỖI THIẾU CLASS KHI DÙNG FFMPEG (GOOGLE PLAY CORE) ---
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# --- BẢO VỆ CẦU NỐI PIGEON CỦA FIREBASE ---
-keep class dev.flutter.pigeon.** { *; }
-keep class io.flutter.plugins.firebase.core.** { *; }
-keep class io.flutter.plugins.firebase.messaging.** { *; }