# react-native-external-scanner

A high-performance React Native library for external barcode/QR code scanner devices. Built with [Nitro Modules](https://github.com/mrousavy/nitro) for direct JSI bindings, eliminating the 5+ second delay common with traditional native modules.

## Features

- **High Performance**: Direct C++ to JavaScript communication via JSI - no bridge delay
- **Cross-Platform**: Works on both iOS and Android
- **No UI Required**: Captures scanner input without needing a focused text input
- **Device Detection**: Automatically detects when scanners connect/disconnect
- **Configurable**: Adjustable scan timeout and minimum length settings
- **React Hooks**: Easy-to-use React hooks for functional components

## Installation

```bash
npm install react-native-external-scanner react-native-nitro-modules
# or
yarn add react-native-external-scanner react-native-nitro-modules
```

### iOS

```bash
cd ios && pod install
```

### Android

For Android, you need to:

1. **Initialize the scanner** in your `MainActivity.kt` or `MainApplication.kt`
2. **Intercept key events** to capture scanner input

Add the following to your `MainActivity.kt`:

```kotlin
import android.os.Bundle
import android.view.KeyEvent
import com.margelo.nitro.externalscanner.ExternalScannerUtil
import com.margelo.nitro.externalscanner.NitroExternalScannerPackage

class MainActivity : ReactActivity() {
    // ... existing code ...

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Initialize scanner detection early
        NitroExternalScannerPackage.initialize(this)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        // Let external scanner handle the event first
        if (ExternalScannerUtil.processKeyEvent(event)) {
            return true // Event consumed by scanner
        }
        return super.dispatchKeyEvent(event)
    }
}
```

**Tip:** To debug connected devices, check logcat for `ExternalScanner` tag:
```bash
adb logcat -s ExternalScanner
```

## Usage

### Using the Hook (Recommended)

```tsx
import { useExternalScanner } from 'react-native-external-scanner'

function ScannerScreen() {
  const { isConnected, lastScan, scanning, start, stop } = useExternalScanner({
    onScan: (result) => {
      console.log('Scanned:', result.code)
      console.log('Timestamp:', result.timestamp)
    },
    // Optional: callback for each character
    onChar: (char, keyCode) => {
      console.log('Character:', char, 'KeyCode:', keyCode)
    },
    // Optional: callback for connection changes
    onConnectionChange: (connected) => {
      console.log('Scanner connected:', connected)
    },
    // Optional configuration
    scanTimeout: 50, // ms between keys (default: 50)
    minScanLength: 3, // minimum characters (default: 3)
    autoStart: true, // auto-start scanning (default: true)
  })

  return (
    <View>
      <Text>Scanner connected: {isConnected ? 'Yes' : 'No'}</Text>
      <Text>Scanning: {scanning ? 'Yes' : 'No'}</Text>
      <Text>Last scan: {lastScan?.code || 'None'}</Text>
      <Button onPress={scanning ? stop : start} title={scanning ? 'Stop' : 'Start'} />
    </View>
  )
}
```

### Simple Connection Check

```tsx
import { useScannerConnection } from 'react-native-external-scanner'

function App() {
  const scannerConnected = useScannerConnection()

  return <Text>Scanner: {scannerConnected ? 'Connected' : 'Not connected'}</Text>
}
```

### Imperative API

```tsx
import {
  hasExternalScanner,
  getConnectedDevices,
  startScanning,
  stopScanning,
  onScannerConnectionChanged,
  setScanTimeout,
  setMinScanLength,
} from 'react-native-external-scanner'

// Check if scanner is connected
const connected = hasExternalScanner()

// Get list of connected devices
const devices = getConnectedDevices()
devices.forEach((device) => {
  console.log(`Device: ${device.name} (ID: ${device.id})`)
})

// Configure scanning
setScanTimeout(50) // ms between keys
setMinScanLength(3) // minimum characters

// Start scanning
startScanning(
  (result) => {
    console.log('Scanned:', result.code)
  },
  (char, keyCode) => {
    // Optional: handle each character
  }
)

// Listen for connection changes
onScannerConnectionChanged((isConnected) => {
  console.log('Scanner connected:', isConnected)
})

// Stop scanning when done
stopScanning()
```

## API Reference

### Types

```typescript
interface DeviceInfo {
  id: number
  name: string
  vendorId: number
  productId: number
  isExternal: boolean
}

interface ScanResult {
  code: string
  timestamp: number
}
```

### Functions

| Function | Description |
|----------|-------------|
| `hasExternalScanner()` | Returns `true` if an external scanner is connected |
| `getConnectedDevices()` | Returns array of connected `DeviceInfo` objects |
| `startScanning(onScan, onChar?)` | Start listening for scans |
| `stopScanning()` | Stop listening for scans |
| `isScanning()` | Returns `true` if currently scanning |
| `onScannerConnectionChanged(callback)` | Register connection change callback |
| `setScanTimeout(ms)` | Set timeout between keys (default: 50ms) |
| `setMinScanLength(length)` | Set minimum scan length (default: 3) |

### Hooks

| Hook | Description |
|------|-------------|
| `useExternalScanner(options)` | Full-featured hook with scanning capabilities |
| `useScannerConnection()` | Simple hook returning connection status |

## How It Works

External barcode scanners typically emulate a keyboard and send characters followed by an Enter key. This library:

1. **Detects** external input devices (keyboards, HID devices)
2. **Intercepts** key events from these devices
3. **Buffers** characters until Enter is pressed or timeout occurs
4. **Delivers** the complete barcode directly to JavaScript via JSI

The C++ implementation ensures minimal latency between the physical scan and your JavaScript callback.

## Performance

Traditional React Native native modules use the bridge, which batches messages and can introduce delays of 5+ seconds in some cases. This library uses:

- **Nitro Modules**: Direct JSI bindings to C++
- **Synchronous callbacks**: No bridge serialization
- **Efficient buffering**: Characters are collected in C++ before being sent to JS

## Platform Notes

### Android
- Uses `InputDevice` API to detect external keyboards/scanners
- Intercepts key events at the Activity level
- Supports device connect/disconnect notifications

### iOS
- Uses `GameController` framework for keyboard detection
- Monitors `GCKeyboard` for external keyboard input
- Supports hardware keyboard connection notifications

## License

MIT
