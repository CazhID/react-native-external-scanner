import { NitroModules } from 'react-native-nitro-modules'
import type { ExternalScanner, DeviceInfo, ScanResult } from './specs/ExternalScanner.nitro'

// Export types
export type { DeviceInfo, ScanResult, ExternalScanner }

// Get the HybridObject instance
const ExternalScannerModule = NitroModules.createHybridObject<ExternalScanner>('ExternalScanner')

/**
 * Check if an external scanner/keyboard is connected
 */
export function hasExternalScanner(): boolean {
  return ExternalScannerModule.hasExternalScanner()
}

/**
 * Get list of connected external input devices
 */
export function getConnectedDevices(): DeviceInfo[] {
  return ExternalScannerModule.getConnectedDevices()
}

/**
 * Start listening for barcode scans
 * @param onScan - Callback when a complete barcode is scanned
 * @param onChar - Optional callback for each character received
 */
export function startScanning(
  onScan: (result: ScanResult) => void,
  onChar?: (char: string, keyCode: number) => void
): void {
  ExternalScannerModule.startScanning(onScan, onChar)
}

/**
 * Stop listening for barcode scans
 */
export function stopScanning(): void {
  ExternalScannerModule.stopScanning()
}

/**
 * Check if currently scanning
 */
export function isScanning(): boolean {
  return ExternalScannerModule.isScanning()
}

/**
 * Register callback for scanner connection changes
 */
export function onScannerConnectionChanged(callback: (isConnected: boolean) => void): void {
  ExternalScannerModule.onScannerConnectionChanged(callback)
}

/**
 * Set scan timeout (ms between keys before considering scan complete)
 * @param timeout - Timeout in milliseconds (default: 50ms)
 */
export function setScanTimeout(timeout: number): void {
  ExternalScannerModule.setScanTimeout(timeout)
}

/**
 * Set minimum scan length (minimum characters before considering valid scan)
 * @param length - Minimum length (default: 3)
 */
export function setMinScanLength(length: number): void {
  ExternalScannerModule.setMinScanLength(length)
}

// Export the raw module for advanced use cases
export { ExternalScannerModule }

// Export React hooks
export {
  useExternalScanner,
  useScannerConnection,
  type UseExternalScannerOptions,
  type UseExternalScannerResult,
} from './hooks'
