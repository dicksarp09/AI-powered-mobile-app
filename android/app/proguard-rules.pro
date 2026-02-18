## ProGuard Rules for whisper_flutter and other native libraries
# Keep whisper.cpp JNI classes
-keep class com.whispercpp.** { *; }
-keepclassmembers class com.whispercpp.** { *; }
# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
