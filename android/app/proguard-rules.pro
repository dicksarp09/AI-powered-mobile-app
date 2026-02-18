## ProGuard Rules for whisper_flutter, llama_flutter and other native libraries
# Keep whisper.cpp JNI classes
-keep class com.whispercpp.** { *; }
-keepclassmembers class com.whispercpp.** { *; }
# Keep llama.cpp JNI classes
-keep class com.llama.** { *; }
-keepclassmembers class com.llama.** { *; }
# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
