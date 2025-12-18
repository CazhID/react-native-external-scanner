package com.margelo.nitro.externalscanner

import android.content.Context
import android.hardware.input.InputManager
import android.util.Log
import android.view.InputDevice
import android.view.KeyCharacterMap
import android.view.KeyEvent

/**
 * Utility class for detecting and working with external scanner devices
 */
object ExternalScannerUtil {
    private const val TAG = "ExternalScanner"

    private var inputManager: InputManager? = null
    private var isIntercepting = false
    private var deviceListener: InputManager.InputDeviceListener? = null
    private var isInitialized = false

    /**
     * Initialize the utility with application context
     */
    @JvmStatic
    fun init(context: Context) {
        if (isInitialized) {
            Log.d(TAG, "Already initialized")
            return
        }
        Log.d(TAG, "Initializing ExternalScannerUtil")
        inputManager = context.getSystemService(Context.INPUT_SERVICE) as? InputManager
        setupDeviceListener()

        // Log all devices for debugging
        logAllDevices()

        syncDevices()
        isInitialized = true

        val devices = getConnectedDevices()
        Log.d(TAG, "Initialization complete. Found ${devices.size} external devices")
        devices.forEach { device ->
            Log.d(TAG, "  - ${device.name} (id=${device.id})")
        }
    }

    /**
     * Check if any external scanner/keyboard is connected
     */
    @JvmStatic
    fun hasExternalScanner(): Boolean {
        val deviceIds = inputManager?.inputDeviceIds ?: InputDevice.getDeviceIds()
        val hasScanner = deviceIds.any { isExternalScanner(it) }
        Log.d(TAG, "hasExternalScanner: $hasScanner (checked ${deviceIds.size} devices)")
        return hasScanner
    }

    /**
     * Debug: List all input devices
     */
    @JvmStatic
    fun logAllDevices() {
        val deviceIds = inputManager?.inputDeviceIds ?: InputDevice.getDeviceIds()
        Log.d(TAG, "=== All Input Devices (${deviceIds.size}) ===")
        for (deviceId in deviceIds) {
            val device = InputDevice.getDevice(deviceId) ?: continue
            val sources = device.sources
            val hasKeyboard = (sources and InputDevice.SOURCE_KEYBOARD) == InputDevice.SOURCE_KEYBOARD
            val keyCharMap = device.keyCharacterMap
            Log.d(TAG, "Device[$deviceId]: ${device.name}")
            Log.d(TAG, "  - isVirtual: ${device.isVirtual}")
            Log.d(TAG, "  - hasKeyboard: $hasKeyboard")
            Log.d(TAG, "  - keyboardType: ${device.keyboardType}")
            Log.d(TAG, "  - keyCharMapType: ${keyCharMap.keyboardType}")
            Log.d(TAG, "  - vendorId: ${device.vendorId}, productId: ${device.productId}")
            Log.d(TAG, "  - isExternalScanner: ${isExternalScannerDevice(device)}")
        }
        Log.d(TAG, "=== End Device List ===")
    }

    /**
     * Get JSON representation of connected devices (for JNI)
     */
    @JvmStatic
    fun getConnectedDevicesJson(): String {
        val devices = getConnectedDevices()
        val sb = StringBuilder("[")
        devices.forEachIndexed { index, device ->
            if (index > 0) sb.append(",")
            sb.append("{")
            sb.append("\"id\":${device.id},")
            sb.append("\"name\":\"${device.name}\",")
            sb.append("\"vendorId\":${device.vendorId},")
            sb.append("\"productId\":${device.productId},")
            sb.append("\"isExternal\":${device.isExternal}")
            sb.append("}")
        }
        sb.append("]")
        return sb.toString()
    }

    /**
     * Get list of connected external input devices
     */
    @JvmStatic
    fun getConnectedDevices(): List<DeviceInfoJava> {
        val devices = mutableListOf<DeviceInfoJava>()
        val deviceIds = inputManager?.inputDeviceIds ?: InputDevice.getDeviceIds()

        for (deviceId in deviceIds) {
            val device = InputDevice.getDevice(deviceId) ?: continue
            if (isExternalScannerDevice(device)) {
                devices.add(
                    DeviceInfoJava(
                        id = device.id,
                        name = device.name,
                        vendorId = device.vendorId,
                        productId = device.productId,
                        isExternal = !device.isVirtual
                    )
                )
            }
        }

        return devices
    }

    /**
     * Start intercepting key events
     */
    @JvmStatic
    fun startIntercepting() {
        Log.d(TAG, "startIntercepting() called")
        isIntercepting = true
        syncDevices()
    }

    /**
     * Stop intercepting key events
     */
    @JvmStatic
    fun stopIntercepting() {
        Log.d(TAG, "stopIntercepting() called")
        isIntercepting = false
    }

    /**
     * Check if currently intercepting
     */
    @JvmStatic
    fun isIntercepting(): Boolean = isIntercepting

    /**
     * Process a key event from an external scanner
     * Call this from Activity.dispatchKeyEvent()
     * Returns true if the event was consumed
     */
    @JvmStatic
    fun processKeyEvent(event: KeyEvent): Boolean {
        val deviceId = event.deviceId
        if (deviceId < 0) return false

        // Check if this is from an external scanner device
        if (!isExternalScanner(deviceId)) return false

        // Log for debugging
        Log.d(TAG, "processKeyEvent: keyCode=${event.keyCode}, action=${event.action}, " +
                "deviceId=$deviceId, isIntercepting=$isIntercepting")

        // If not intercepting, still check but don't consume
        // This allows the event to pass through when scanning is not active
        if (!isIntercepting) {
            Log.d(TAG, "Not intercepting - call startScanning() first")
            return false
        }

        // Get the character for this key event
        val unicodeChar = event.unicodeChar
        val characters = if (unicodeChar != 0 && unicodeChar != KeyCharacterMap.COMBINING_ACCENT) {
            unicodeChar.toChar().toString()
        } else {
            ""
        }

        Log.d(TAG, "Sending to native: char='$characters', keyCode=${event.keyCode}")

        // Send to native
        ExternalScannerJNI.sendKeyEvent(
            keyCode = event.keyCode,
            action = event.action,
            characters = characters,
            deviceId = deviceId
        )

        // Consume the event to prevent it from going to other views
        return true
    }

    /**
     * Check if a device ID corresponds to an external scanner
     */
    @JvmStatic
    fun isExternalScanner(deviceId: Int): Boolean {
        val device = InputDevice.getDevice(deviceId) ?: return false
        return isExternalScannerDevice(device)
    }

    /**
     * Check if an InputDevice is an external scanner
     * Note: Most barcode scanners appear as USB HID keyboards
     */
    private fun isExternalScannerDevice(device: InputDevice): Boolean {
        // Virtual devices are not external scanners
        if (device.isVirtual) return false

        val nameLower = device.name.lowercase()

        // Exclude known internal/system devices
        val isInternalDevice = nameLower.contains("mtk-") ||      // MediaTek internal
                nameLower.contains("pmic") ||                      // Power management
                nameLower.contains("_ts") ||                       // Touchscreen
                nameLower.contains("touchscreen") ||
                nameLower.contains("touch screen") ||
                nameLower.contains("headset") ||                   // Audio jack
                nameLower.contains("headphone") ||
                nameLower.contains("gpio") ||                      // GPIO keys
                nameLower.contains("power") ||                     // Power button
                nameLower.contains("volume") ||                    // Volume buttons
                nameLower.contains("fingerprint") ||               // Fingerprint sensor
                nameLower.contains("accelerometer") ||             // Sensors
                nameLower.contains("gyroscope") ||
                nameLower.contains("compass") ||
                nameLower.contains("proximity") ||
                nameLower.contains("light sensor") ||
                nameLower.startsWith("gpio-") ||
                nameLower.startsWith("kpd") ||                     // Keypad (internal)
                nameLower.endsWith("-kpd") ||
                nameLower.contains(",pen")                         // Stylus pen

        if (isInternalDevice) {
            return false
        }

        // Must have keyboard source for scanner input
        val sources = device.sources
        val hasKeyboard = (sources and InputDevice.SOURCE_KEYBOARD) == InputDevice.SOURCE_KEYBOARD

        if (!hasKeyboard) return false

        // Check device name for common scanner/RFID identifiers
        val isLikelyScanner = nameLower.contains("scanner") ||
                nameLower.contains("barcode") ||
                nameLower.contains("reader") ||
                nameLower.contains("rfid") ||
                nameLower.contains("symbol") ||
                nameLower.contains("honeywell") ||
                nameLower.contains("zebra") ||
                nameLower.contains("datalogic") ||
                nameLower.contains("newland") ||
                nameLower.contains("opticon") ||
                nameLower.contains("motorola") ||
                nameLower.contains("intermec") ||
                nameLower.contains("denso") ||
                nameLower.contains("keyence")

        // If it looks like a scanner, accept it
        if (isLikelyScanner) {
            return true
        }

        // For other keyboard devices, require USB vendor/product IDs
        // This filters out built-in keyboards that don't have USB IDs
        val hasUsbIds = device.vendorId > 0 && device.productId > 0

        return hasUsbIds
    }

    /**
     * Setup device connection listener
     */
    private fun setupDeviceListener() {
        deviceListener?.let { inputManager?.unregisterInputDeviceListener(it) }

        deviceListener = object : InputManager.InputDeviceListener {
            override fun onInputDeviceAdded(deviceId: Int) {
                val device = InputDevice.getDevice(deviceId) ?: return
                if (isExternalScannerDevice(device)) {
                    ExternalScannerJNI.notifyDeviceConnected(
                        DeviceInfoJava(
                            id = device.id,
                            name = device.name,
                            vendorId = device.vendorId,
                            productId = device.productId,
                            isExternal = !device.isVirtual
                        )
                    )
                }
            }

            override fun onInputDeviceRemoved(deviceId: Int) {
                ExternalScannerJNI.notifyDeviceDisconnected(deviceId)
            }

            override fun onInputDeviceChanged(deviceId: Int) {
                // Re-sync on changes
                syncDevices()
            }
        }

        inputManager?.registerInputDeviceListener(deviceListener, null)
    }

    /**
     * Sync all connected devices to native
     */
    private fun syncDevices() {
        try {
            val devices = getConnectedDevices()
            ExternalScannerJNI.syncDevices(devices)
        } catch (e: Exception) {
            // JNI might not be ready yet during early init
        }
    }

    /**
     * Cleanup when no longer needed
     */
    @JvmStatic
    fun cleanup() {
        deviceListener?.let { inputManager?.unregisterInputDeviceListener(it) }
        deviceListener = null
        isIntercepting = false
    }
}
