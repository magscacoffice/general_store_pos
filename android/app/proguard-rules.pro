# The app uses ML Kit Latin text recognition only. The plugin references
# optional script-specific recognizer classes that are not packaged.
# Suppress R8 warnings for those optional recognizers; do not suppress ML Kit
# warnings globally or disable release minification.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
