# Bỏ qua cảnh báo và giữ lại code của thư viện uCrop
-dontwarn com.yalantis.ucrop.**
-keep class com.yalantis.ucrop.** { *; }
-keep interface com.yalantis.ucrop.** { *; }

# Bỏ qua cảnh báo và giữ lại thư viện okhttp3 (mà uCrop cần)
-dontwarn okhttp3.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

-dontwarn okio.**