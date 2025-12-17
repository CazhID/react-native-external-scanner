import type { HybridObject } from 'react-native-nitro-modules'

/**
 * Information about a connected input device
 */
export interface DeviceInfo {
  id: number
  name: string
  vendorId: number
  productId: number
  isExternal: boolean
}

/**
 * Result of a barcode scan
 */
export interface ScanResult {
  code: string
  timestamp: number
}

/**
 * ExternalScanner Nitro module - provides direct JSI bindings for
 * high-performance barcode scanner input handling
 */
export interface ExternalScanner extends HybridObject<{
  ios: 'c++'
  android: 'c++'
}> {
  /**
   * Check if an external scanner/keyboard is connected
   */
  hasExternalScanner(): boolean

  /**
   * Get list of connected external input devices
   */
  getConnectedDevices(): DeviceInfo[]

  /**
   * Register callback for scanner connection changes
   */
  onScannerConnectionChanged(callback: (isConnected: boolean) => void): void

  /**
   * Start listening for barcode scans
   * @param onScan - Callback when a complete barcode is scanned
   * @param onChar - Optional callback for each character received
   */
  startScanning(
    onScan: (result: ScanResult) => void,
    onChar?: (char: string, keyCode: number) => void
  ): void

  /**
   * Stop listening for barcode scans
   */
  stopScanning(): void

  /**
   * Check if currently scanning
   */
  isScanning(): boolean

  /**
   * Set scan timeout (ms between keys)
   */
  setScanTimeout(timeout: number): void

  /**
   * Set minimum scan length
   */
  setMinScanLength(length: number): void
}
