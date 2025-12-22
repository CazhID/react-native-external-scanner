#include "HybridExternalScanner_android.hpp"
#include <android/log.h>

#define LOG_TAG "ExternalScanner"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace margelo::nitro::externalscanner {

std::shared_ptr<HybridExternalScannerAndroid> HybridExternalScannerAndroid::_instance = nullptr;
std::mutex HybridExternalScannerAndroid::_instanceMutex;

JavaVM* HybridExternalScannerAndroid::_jvm = nullptr;
jclass HybridExternalScannerAndroid::_scannerUtilClass = nullptr;
jmethodID HybridExternalScannerAndroid::_hasExternalScannerMethod = nullptr;
jmethodID HybridExternalScannerAndroid::_getConnectedDevicesMethod = nullptr;
jmethodID HybridExternalScannerAndroid::_startInterceptingMethod = nullptr;
jmethodID HybridExternalScannerAndroid::_stopInterceptingMethod = nullptr;

HybridExternalScannerAndroid::HybridExternalScannerAndroid()
    : HybridObject(TAG), HybridExternalScanner() {
    LOGD("HybridExternalScannerAndroid created");
}

HybridExternalScannerAndroid::~HybridExternalScannerAndroid() {
    LOGD("HybridExternalScannerAndroid destroyed");
    stopScanning();
}

std::shared_ptr<HybridExternalScannerAndroid> HybridExternalScannerAndroid::getInstance() {
    std::lock_guard<std::mutex> lock(_instanceMutex);
    if (!_instance) {
        _instance = std::make_shared<HybridExternalScannerAndroid>();
    }
    return _instance;
}

void HybridExternalScannerAndroid::initJNI(JNIEnv* env) {
    if (_scannerUtilClass != nullptr) {
        return; // Already initialized
    }

    jclass localClass = env->FindClass("com/margelo/nitro/externalscanner/ExternalScannerUtil");
    if (localClass == nullptr) {
        LOGE("Failed to find ExternalScannerUtil class");
        return;
    }

    _scannerUtilClass = (jclass)env->NewGlobalRef(localClass);
    env->DeleteLocalRef(localClass);

    _hasExternalScannerMethod = env->GetStaticMethodID(_scannerUtilClass, "hasExternalScanner", "()Z");
    _getConnectedDevicesMethod = env->GetStaticMethodID(_scannerUtilClass, "getConnectedDevicesJson", "()Ljava/lang/String;");
    _startInterceptingMethod = env->GetStaticMethodID(_scannerUtilClass, "startIntercepting", "()V");
    _stopInterceptingMethod = env->GetStaticMethodID(_scannerUtilClass, "stopIntercepting", "()V");

    if (!_hasExternalScannerMethod || !_getConnectedDevicesMethod) {
        LOGE("Failed to find JNI methods");
    }
}

JNIEnv* HybridExternalScannerAndroid::getJNIEnv() {
    if (_jvm == nullptr) {
        LOGE("JVM not initialized");
        return nullptr;
    }

    JNIEnv* env = nullptr;
    jint result = _jvm->GetEnv((void**)&env, JNI_VERSION_1_6);

    if (result == JNI_EDETACHED) {
        if (_jvm->AttachCurrentThread(&env, nullptr) != JNI_OK) {
            LOGE("Failed to attach thread");
            return nullptr;
        }
    } else if (result != JNI_OK) {
        LOGE("Failed to get JNI env");
        return nullptr;
    }

    // Initialize JNI references if not already done
    if (env != nullptr && _scannerUtilClass == nullptr) {
        initJNI(env);
    }

    return env;
}

bool HybridExternalScannerAndroid::hasExternalScanner() {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || _scannerUtilClass == nullptr || _hasExternalScannerMethod == nullptr) {
        // Fallback to base class
        return HybridExternalScanner::hasExternalScanner();
    }

    jboolean result = env->CallStaticBooleanMethod(_scannerUtilClass, _hasExternalScannerMethod);
    return result == JNI_TRUE;
}

std::vector<DeviceInfo> HybridExternalScannerAndroid::getConnectedDevices() {
    // Return cached devices (updated via JNI callbacks)
    return HybridExternalScanner::getConnectedDevices();
}

void HybridExternalScannerAndroid::startScanning(
    const std::function<void(const ScanResult&)>& onScan,
    const std::optional<std::function<void(const std::string&, double)>>& onChar
) {
    LOGD("startScanning() called");
    HybridExternalScanner::startScanning(onScan, onChar);

    JNIEnv* env = getJNIEnv();
    if (env != nullptr && _scannerUtilClass != nullptr && _startInterceptingMethod != nullptr) {
        LOGD("Calling ExternalScannerUtil.startIntercepting()");
        env->CallStaticVoidMethod(_scannerUtilClass, _startInterceptingMethod);
        LOGD("ExternalScannerUtil.startIntercepting() called successfully");
    } else {
        LOGE("Failed to call startIntercepting: env=%p, class=%p, method=%p",
             env, _scannerUtilClass, _startInterceptingMethod);
    }

    LOGD("Started scanning, isScanning=%d", isScanning() ? 1 : 0);
}

void HybridExternalScannerAndroid::stopScanning() {
    HybridExternalScanner::stopScanning();

    JNIEnv* env = getJNIEnv();
    if (env != nullptr && _scannerUtilClass != nullptr && _stopInterceptingMethod != nullptr) {
        env->CallStaticVoidMethod(_scannerUtilClass, _stopInterceptingMethod);
    }

    LOGD("Stopped scanning");
}

// Static JNI callback methods
void HybridExternalScannerAndroid::onKeyEventFromJava(JNIEnv* env, int keyCode, int action, jstring characters, int deviceId) {
    auto instance = getInstance();
    if (instance && instance->isScanning()) {
        const char* chars = env->GetStringUTFChars(characters, nullptr);
        std::string charStr(chars);
        env->ReleaseStringUTFChars(characters, chars);

        instance->onKeyEvent(keyCode, action, charStr, deviceId);
    }
}

void HybridExternalScannerAndroid::onDeviceConnectedFromJava(JNIEnv* env, int id, jstring name, int vendorId, int productId, bool isExternal) {
    auto instance = getInstance();
    if (instance) {
        const char* nameChars = env->GetStringUTFChars(name, nullptr);
        std::string nameStr(nameChars);
        env->ReleaseStringUTFChars(name, nameChars);

        DeviceInfo device(static_cast<double>(id), nameStr, static_cast<double>(vendorId), static_cast<double>(productId), isExternal);
        instance->onDeviceConnected(device);
    }
}

void HybridExternalScannerAndroid::onDeviceDisconnectedFromJava(JNIEnv* env, int deviceId) {
    auto instance = getInstance();
    if (instance) {
        instance->onDeviceDisconnected(deviceId);
    }
}

void HybridExternalScannerAndroid::setDevicesFromJava(JNIEnv* env, jobjectArray devices) {
    auto instance = getInstance();
    if (!instance) return;

    // Clear existing devices
    {
        std::lock_guard<std::mutex> lock(instance->_devicesMutex);
        instance->_connectedDevices.clear();
    }

    if (devices == nullptr) {
        LOGD("setDevicesFromJava: devices array is null");
        return;
    }

    // Get array length
    jsize length = env->GetArrayLength(devices);
    LOGD("setDevicesFromJava: processing %d devices", length);

    if (length == 0) {
        return;
    }

    // Get the DeviceInfoJava class and its fields
    jclass deviceClass = env->FindClass("com/margelo/nitro/externalscanner/DeviceInfoJava");
    if (deviceClass == nullptr) {
        LOGE("Failed to find DeviceInfoJava class");
        env->ExceptionClear();
        return;
    }

    jfieldID idField = env->GetFieldID(deviceClass, "id", "I");
    if (env->ExceptionCheck() || idField == nullptr) {
        LOGE("Failed to find 'id' field - ProGuard may have obfuscated it. Add keep rules!");
        env->ExceptionClear();
        env->DeleteLocalRef(deviceClass);
        return;
    }

    jfieldID nameField = env->GetFieldID(deviceClass, "name", "Ljava/lang/String;");
    if (env->ExceptionCheck() || nameField == nullptr) {
        LOGE("Failed to find 'name' field");
        env->ExceptionClear();
        env->DeleteLocalRef(deviceClass);
        return;
    }

    jfieldID vendorIdField = env->GetFieldID(deviceClass, "vendorId", "I");
    if (env->ExceptionCheck() || vendorIdField == nullptr) {
        LOGE("Failed to find 'vendorId' field");
        env->ExceptionClear();
        env->DeleteLocalRef(deviceClass);
        return;
    }

    jfieldID productIdField = env->GetFieldID(deviceClass, "productId", "I");
    if (env->ExceptionCheck() || productIdField == nullptr) {
        LOGE("Failed to find 'productId' field");
        env->ExceptionClear();
        env->DeleteLocalRef(deviceClass);
        return;
    }

    jfieldID isExternalField = env->GetFieldID(deviceClass, "isExternal", "Z");
    if (env->ExceptionCheck() || isExternalField == nullptr) {
        LOGE("Failed to find 'isExternal' field");
        env->ExceptionClear();
        env->DeleteLocalRef(deviceClass);
        return;
    }

    for (jsize i = 0; i < length; i++) {
        jobject deviceObj = env->GetObjectArrayElement(devices, i);
        if (deviceObj == nullptr) {
            continue;
        }

        jint id = env->GetIntField(deviceObj, idField);
        jstring nameJStr = (jstring)env->GetObjectField(deviceObj, nameField);
        jint vendorId = env->GetIntField(deviceObj, vendorIdField);
        jint productId = env->GetIntField(deviceObj, productIdField);
        jboolean isExternal = env->GetBooleanField(deviceObj, isExternalField);

        std::string nameStr;
        if (nameJStr != nullptr) {
            const char* nameChars = env->GetStringUTFChars(nameJStr, nullptr);
            if (nameChars != nullptr) {
                nameStr = std::string(nameChars);
                env->ReleaseStringUTFChars(nameJStr, nameChars);
            }
            env->DeleteLocalRef(nameJStr);
        }

        DeviceInfo device(static_cast<double>(id), nameStr, static_cast<double>(vendorId), static_cast<double>(productId), isExternal);
        LOGD("setDevicesFromJava: added device id=%d name=%s", id, nameStr.c_str());

        {
            std::lock_guard<std::mutex> lock(instance->_devicesMutex);
            instance->_connectedDevices.push_back(device);
        }

        env->DeleteLocalRef(deviceObj);
    }

    env->DeleteLocalRef(deviceClass);
    LOGD("setDevicesFromJava: done, total devices=%zu", instance->_connectedDevices.size());
}

} // namespace margelo::nitro::externalscanner

// JNI exports for Java/Kotlin to call native methods
extern "C" {

JNIEXPORT void JNICALL Java_com_margelo_nitro_externalscanner_ExternalScannerJNI_nativeOnKeyEvent(
    JNIEnv* env, jclass clazz, jint keyCode, jint action, jstring characters, jint deviceId) {
    margelo::nitro::externalscanner::HybridExternalScannerAndroid::onKeyEventFromJava(
        env, keyCode, action, characters, deviceId);
}

JNIEXPORT void JNICALL Java_com_margelo_nitro_externalscanner_ExternalScannerJNI_nativeOnDeviceConnected(
    JNIEnv* env, jclass clazz, jint id, jstring name, jint vendorId, jint productId, jboolean isExternal) {
    margelo::nitro::externalscanner::HybridExternalScannerAndroid::onDeviceConnectedFromJava(
        env, id, name, vendorId, productId, isExternal);
}

JNIEXPORT void JNICALL Java_com_margelo_nitro_externalscanner_ExternalScannerJNI_nativeOnDeviceDisconnected(
    JNIEnv* env, jclass clazz, jint deviceId) {
    margelo::nitro::externalscanner::HybridExternalScannerAndroid::onDeviceDisconnectedFromJava(env, deviceId);
}

JNIEXPORT void JNICALL Java_com_margelo_nitro_externalscanner_ExternalScannerJNI_nativeSetDevices(
    JNIEnv* env, jclass clazz, jobjectArray devices) {
    margelo::nitro::externalscanner::HybridExternalScannerAndroid::setDevicesFromJava(env, devices);
}

}
