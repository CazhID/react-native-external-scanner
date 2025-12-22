# Keep DeviceInfoJava class and all its fields for JNI access
-keep class com.margelo.nitro.externalscanner.DeviceInfoJava {
    *;
}

# Keep ExternalScannerJNI class and methods
-keep class com.margelo.nitro.externalscanner.ExternalScannerJNI {
    *;
}

# Keep ExternalScannerUtil class and methods
-keep class com.margelo.nitro.externalscanner.ExternalScannerUtil {
    *;
}

# Keep all native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
