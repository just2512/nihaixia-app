# Flutter插件已内嵌自己的consumer规则，无需手动keep
# 删除了：io.flutter.** / sqflite / path_provider / share_plus 规则

# 保留MainActivity（MethodChannel反射调用）
-keep class com.nihaisha.nihaisha_app.MainActivity { *; }

# 保留FileProvider（安装APK需要）
-keep class androidx.core.content.FileProvider { *; }

# 保留 LiteRT-LM JNI 类（R8 会剥离/改名 NativeLibraryLoader 等 JNI 绑定，
# 导致 "No implementation found for nativeCheckLoaded" 与 LiteRtLmJniException）
-keep class com.google.ai.edge.litertlm.** { *; }
-keepclassmembers class com.google.ai.edge.litertlm.** { *; }
