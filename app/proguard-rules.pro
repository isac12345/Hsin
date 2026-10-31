# Aturan keep minimal untuk R8. Hanya kelas yang dipanggil lewat nama string
# atau refleksi; sisanya biarkan disusutkan.
#
# Komponen yang disebut di AndroidManifest (AGP juga membuat aturan otomatis,
# ini eksplisit supaya tidak bergantung pada versi AGP).
-keep class com.hsin.MainActivity { *; }
-keep class com.hsin.BubbleService { *; }
-keep class com.hsin.ProfileTileService { *; }
-keep class com.hsin.BootReceiver { *; }

# ViewModel dibuat lewat refleksi oleh android.viewModels()/ViewModelProvider.
-keepclassmembers,allowobfuscation class * extends androidx.lifecycle.ViewModel {
    <init>();
}
