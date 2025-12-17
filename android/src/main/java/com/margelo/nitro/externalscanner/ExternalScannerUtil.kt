package com.margelo.nitro.externalscanner

import android.content.Context
import android.hardware.input.InputManager
import android.view.InputDevice
import android.view.KeyCharacterMap
import android.view.KeyEvent

/**
 * Utility class for detecting and working with external scanner devices
 */
object ExternalScannerUtil {
    private var inputManager: InputManager? = null
    private var isIntercepting = false
    private var deviceListener: InputManager.InputDeviceListener? = null

    /**
     * Initialize the utility with application context
     */
    @JvmStatic
    fun init(context: Context) {
        inputManager = context.getSystemService(Context.INPUT_SERVICE) as? InputManager
        setupDeviceListener()
        syncDevices()
    }

    /**
     * Check if any external scanner/keyboard is connected
     */
    @JvmStatic
    fun hasExternalScanner(): Boolean {
        val deviceIds = inputManager?.inputDeviceIds ?: InputDevice.getDeviceIds()
        return deviceIds.any { isExternalScanner(it) }
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
        isIntercepting = true
        syncDevices()
    }

    /**
     * Stop intercepting key events
     */
    @JvmStatic
    fun stopIntercepting() {
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
        if (!isIntercepting) return false

        val deviceId = event.deviceId
        if (deviceId < 0) return false

        // Check if this is from an external device
        if (!isExternalScanner(deviceId)) return false

        // Get the character for this key event
        val unicodeChar = event.unicodeChar
        val characters = if (unicodeChar != 0 && unicodeChar != KeyCharacterMap.COMBINING_ACCENT) {
            unicodeChar.toChar().toString()
        } else {
            ""
        }

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
     */
    private fun isExternalScannerDevice(device: InputDevice): Boolean {
        // Virtual devices are not external scanners
        if (device.isVirtual) return false

        // Must have keyboard source
        val sources = device.sources
        val hasKeyboard = (sources and InputDevice.SOURCE_KEYBOARD) == InputDevice.SOURCE_KEYBOARD

        if (!hasKeyboard) return false

        // Check for valid key character map (excludes system keyboards)
        val keyCharMap = device.keyCharacterMap
        if (keyCharMap.keyboardType == KeyCharacterMap.VIRTUAL_KEYBOARD) {
            return false
        }

        // Additional heuristic: check device name for common scanner identifiers
        val nameLower = device.name.lowercase()
        val isLikelyScanner = nameLower.contains("scanner") ||
                nameLower.contains("barcode") ||
                nameLower.contains("reader") ||
                nameLower.contains("hid") ||
                nameLower.contains("symbol") ||
                nameLower.contains("honeywell") ||
                nameLower.contains("zebra") ||
                nameLower.contains("datalogic")

        // If it's an external keyboard-like device, treat it as a potential scanner
        // Scanners typically appear as HID keyboard devices
        val isExternalKeyboard = device.keyboardType != InputDevice.KEYBOARD_TYPE_NONE &&
                !device.isVirtual &&
                keyCharMap.keyboardType != KeyCharacterMap.VIRTUAL_KEYBOARD

        return isLikelyScanner || isExternalKeyboard
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
