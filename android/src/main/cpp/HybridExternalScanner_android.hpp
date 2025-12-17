#pragma once

#include "HybridExternalScanner.hpp"
#include <jni.h>

namespace margelo::nitro::externalscanner {

class HybridExternalScannerAndroid : public HybridExternalScanner {
public:
    HybridExternalScannerAndroid();
    ~HybridExternalScannerAndroid() override;

    // Override to add Android-specific device detection
    bool hasExternalScanner() override;
    std::vector<DeviceInfo> getConnectedDevices() override;
    void startScanning(
        const std::function<void(const ScanResult&)>& onScan,
        const std::optional<std::function<void(const std::string&, double)>>& onChar
    ) override;
    void stopScanning() override;

    // JNI methods called from Java/Kotlin
    static void onKeyEventFromJava(JNIEnv* env, int keyCode, int action, jstring characters, int deviceId);
    static void onDeviceConnectedFromJava(JNIEnv* env, int id, jstring name, int vendorId, int productId, bool isExternal);
    static void onDeviceDisconnectedFromJava(JNIEnv* env, int deviceId);
    static void setDevicesFromJava(JNIEnv* env, jobjectArray devices);

    // Get the singleton instance
    static std::shared_ptr<HybridExternalScannerAndroid> getInstance();

    // JVM reference - needs to be public for cpp-adapter to set it
    static JavaVM* _jvm;

private:
    static std::shared_ptr<HybridExternalScannerAndroid> _instance;
    static std::mutex _instanceMutex;

    // Cache JNI references
    static jclass _scannerUtilClass;
    static jmethodID _hasExternalScannerMethod;
    static jmethodID _getConnectedDevicesMethod;
    static jmethodID _startInterceptingMethod;
    static jmethodID _stopInterceptingMethod;

    void initJNI(JNIEnv* env);
    JNIEnv* getJNIEnv();
};

} // namespace margelo::nitro::externalscanner

// JNI function declarations
extern "C" {
    JNIEXPORT void JNICALL Java_com_margelo_nitro_externalscanner_ExternalScannerJNI_nativeOnKeyEvent(
        JNIEnv* env, jclass clazz, jint keyCode, jint action, jstring characters, jint deviceId);

    JNIEXPORT void JNICALL Java_com_margelo_nitro_externalscanner_ExternalScannerJNI_nativeOnDeviceConnected(
        JNIEnv* env, jclass clazz, jint id, jstring name, jint vendorId, jint productId, jboolean isExternal);

    JNIEXPORT void JNICALL Java_com_margelo_nitro_externalscanner_ExternalScannerJNI_nativeOnDeviceDisconnected(
        JNIEnv* env, jclass clazz, jint deviceId);

    JNIEXPORT void JNICALL Java_com_margelo_nitro_externalscanner_ExternalScannerJNI_nativeSetDevices(
        JNIEnv* env, jclass clazz, jobjectArray devices);
}
