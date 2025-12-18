import { useEffect, useState, useCallback, useRef } from 'react'
import {
  hasExternalScanner,
  getConnectedDevices,
  startScanning,
  stopScanning,
  onScannerConnectionChanged,
  setScanTimeout,
  setMinScanLength,
} from './index'
import type { DeviceInfo, ScanResult } from './specs/ExternalScanner.nitro'

export interface UseExternalScannerOptions {
  /** Auto-start scanning when hook mounts (default: true) */
  autoStart?: boolean
  /** Scan timeout in ms (default: 50ms) */
  scanTimeout?: number
  /** Minimum scan length (default: 3) */
  minScanLength?: number
  /** Callback when a barcode is scanned */
  onScan?: (result: ScanResult) => void
  /** Callback for each character received */
  onChar?: (char: string, keyCode: number) => void
  /** Callback when scanner connection changes */
  onConnectionChange?: (isConnected: boolean) => void
}

export interface UseExternalScannerResult {
  /** Whether an external scanner is connected */
  isConnected: boolean
  /** List of connected devices */
  devices: DeviceInfo[]
  /** Whether currently scanning */
  scanning: boolean
  /** Last scanned code */
  lastScan: ScanResult | null
  /** Start scanning */
  start: () => void
  /** Stop scanning */
  stop: () => void
  /** Refresh device list */
  refreshDevices: () => void
}

/**
 * React hook for external scanner functionality
 *
 * @example
 * ```tsx
 * function ScannerScreen() {
 *   const { isConnected, lastScan, scanning, start, stop } = useExternalScanner({
 *     onScan: (result) => {
 *       console.log('Scanned:', result.code)
 *     }
 *   })
 *
 *   return (
 *     <View>
 *       <Text>Scanner connected: {isConnected ? 'Yes' : 'No'}</Text>
 *       <Text>Scanning: {scanning ? 'Yes' : 'No'}</Text>
 *       <Text>Last scan: {lastScan?.code || 'None'}</Text>
 *       <Button onPress={scanning ? stop : start}>
 *         {scanning ? 'Stop' : 'Start'}
 *       </Button>
 *     </View>
 *   )
 * }
 * ```
 */
export function useExternalScanner(
  options: UseExternalScannerOptions = {}
): UseExternalScannerResult {
  const {
    autoStart = true,
    scanTimeout = 50,
    minScanLength = 3,
    onScan,
    onChar,
    onConnectionChange,
  } = options

  const [isConnected, setIsConnected] = useState(() => hasExternalScanner())
  const [devices, setDevices] = useState<DeviceInfo[]>(() => getConnectedDevices())
  const [scanning, setScanning] = useState(false)
  const [lastScan, setLastScan] = useState<ScanResult | null>(null)

  // Use refs to avoid stale closures
  const onScanRef = useRef(onScan)
  const onCharRef = useRef(onChar)
  onScanRef.current = onScan
  onCharRef.current = onChar

  const refreshDevices = useCallback(() => {
    setDevices(getConnectedDevices())
    setIsConnected(hasExternalScanner())
  }, [])

  const handleScan = useCallback((result: ScanResult) => {
    setLastScan(result)
    onScanRef.current?.(result)
  }, [])

  const handleChar = useCallback((char: string, keyCode: number) => {
    onCharRef.current?.(char, keyCode)
  }, [])

  // Use ref to track scanning state to avoid stale closures
  const scanningRef = useRef(false)

  const start = useCallback(() => {
    if (scanningRef.current) return
    setScanTimeout(scanTimeout)
    setMinScanLength(minScanLength)
    startScanning(handleScan, handleChar)
    scanningRef.current = true
    setScanning(true)
  }, [scanTimeout, minScanLength, handleScan, handleChar])

  const stop = useCallback(() => {
    if (!scanningRef.current) return
    stopScanning()
    scanningRef.current = false
    setScanning(false)
  }, [])

  // Setup connection listener
  useEffect(() => {
    onScannerConnectionChanged((connected) => {
      setIsConnected(connected)
      refreshDevices()
      onConnectionChange?.(connected)
    })
  }, [refreshDevices, onConnectionChange])

  // Auto-start scanning
  useEffect(() => {
    if (autoStart) {
      // Direct call to native to avoid any stale closure issues
      setScanTimeout(scanTimeout)
      setMinScanLength(minScanLength)
      startScanning(handleScan, handleChar)
      scanningRef.current = true
      setScanning(true)
    }
    return () => {
      if (scanningRef.current) {
        stopScanning()
        scanningRef.current = false
      }
    }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  return {
    isConnected,
    devices,
    scanning,
    lastScan,
    start,
    stop,
    refreshDevices,
  }
}

/**
 * Simple hook to check scanner connection status
 *
 * @example
 * ```tsx
 * function App() {
 *   const scannerConnected = useScannerConnection()
 *   return <Text>Scanner: {scannerConnected ? 'Connected' : 'Not connected'}</Text>
 * }
 * ```
 */
export function useScannerConnection(): boolean {
  const [isConnected, setIsConnected] = useState(() => hasExternalScanner())

  useEffect(() => {
    // Check initial state
    setIsConnected(hasExternalScanner())

    // Listen for changes
    onScannerConnectionChanged(setIsConnected)
  }, [])

  return isConnected
}
