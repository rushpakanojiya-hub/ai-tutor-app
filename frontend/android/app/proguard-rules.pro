# google_mlkit_text_recognition ships optional language-specific
# recognizers (Chinese/Devanagari/Japanese/Korean) as separate artifacts.
# This app only uses the default (Latin) recognizer, so those classes
# genuinely aren't present as dependencies - R8 just needs to be told
# that's expected, not an error.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
