#pragma once

#include "HybridExternalScannerSpec.hpp"
#include <mutex>
#include <atomic>
#include <chrono>
#include <thread>

namespace margelo::nitro::externalscanner {

class HybridExternalScanner : public HybridExternalScannerSpec {
public:
    HybridExternalScanner();
    ~HybridExternalScanner() override;

    // HybridExternalScannerSpec implementation
    bool hasExternalScanner() override;
    std::vector<DeviceInfo> getConnectedDevices() override;
    void onScannerConnectionChanged(const std::function<void(bool)>& callback) override;
    void startScanning(
        const std::function<void(const ScanResult&)>& onScan,
        const std::optional<std::function<void(const std::string&, double)>>& onChar
    ) override;
    void stopScanning() override;
    bool isScanning() override;
    void setScanTimeout(double timeout) override;
    void setMinScanLength(double length) override;

    // Platform-specific methods to be called from native code
    void onKeyEvent(int keyCode, int action, const std::string& characters, int deviceId);
    void onDeviceConnected(const DeviceInfo& device);
    void onDeviceDisconnected(int deviceId);

protected:
    // Buffer for accumulating scan characters
    std::string _scanBuffer;
    std::chrono::steady_clock::time_point _lastKeyTime;

    // Configuration
    double _scanTimeout = 50.0; // ms between keys (scanners are fast)
    double _minScanLength = 3.0;

    // State
    std::atomic<bool> _isScanning{false};
    std::vector<DeviceInfo> _connectedDevices;
    std::mutex _devicesMutex;
    std::mutex _bufferMutex;

    // Callbacks
    std::function<void(const ScanResult&)> _onScanCallback;
    std::optional<std::function<void(const std::string&, double)>> _onCharCallback;
    std::function<void(bool)> _connectionCallback;

    // Helper methods
    void processBuffer();
    void clearBuffer();
    bool isEnterKey(int keyCode);
    std::string keyCodeToChar(int keyCode, bool shiftPressed);
};

} // namespace margelo::nitro::externalscanner
