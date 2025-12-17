package com.margelo.nitro.externalscanner

/**
 * JNI bridge for ExternalScanner native module
 * This class provides methods to call from Kotlin into C++
 * and static methods that C++ calls back into Kotlin
 */
object ExternalScannerJNI {
    init {
        System.loadLibrary("NitroExternalScanner")
    }

    // Native methods - called from Kotlin to C++
    @JvmStatic
    external fun nativeOnKeyEvent(keyCode: Int, action: Int, characters: String, deviceId: Int)

    @JvmStatic
    external fun nativeOnDeviceConnected(id: Int, name: String, vendorId: Int, productId: Int, isExternal: Boolean)

    @JvmStatic
    external fun nativeOnDeviceDisconnected(deviceId: Int)

    @JvmStatic
    external fun nativeSetDevices(devices: Array<DeviceInfoJava>)

    // Helper to send key events to native
    fun sendKeyEvent(keyCode: Int, action: Int, characters: String, deviceId: Int) {
        nativeOnKeyEvent(keyCode, action, characters, deviceId)
    }

    // Helper to notify device connection
    fun notifyDeviceConnected(device: DeviceInfoJava) {
        nativeOnDeviceConnected(device.id, device.name, device.vendorId, device.productId, device.isExternal)
    }

    // Helper to notify device disconnection
    fun notifyDeviceDisconnected(deviceId: Int) {
        nativeOnDeviceDisconnected(deviceId)
    }

    // Helper to sync all devices
    fun syncDevices(devices: List<DeviceInfoJava>) {
        nativeSetDevices(devices.toTypedArray())
    }
}

/**
 * Java-friendly device info class for JNI marshalling
 */
data class DeviceInfoJava(
    @JvmField val id: Int,
    @JvmField val name: String,
    @JvmField val vendorId: Int,
    @JvmField val productId: Int,
    @JvmField val isExternal: Boolean
)
