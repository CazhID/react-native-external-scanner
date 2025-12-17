#pragma once

#include "HybridExternalScanner.hpp"

namespace margelo::nitro::externalscanner {

class HybridExternalScannerIOS : public HybridExternalScanner {
public:
    HybridExternalScannerIOS();
    ~HybridExternalScannerIOS() override;

    // Override to add iOS-specific device detection
    bool hasExternalScanner() override;
    std::vector<DeviceInfo> getConnectedDevices() override;
    void startScanning(
        const std::function<void(const ScanResult&)>& onScan,
        const std::optional<std::function<void(const std::string&, double)>>& onChar
    ) override;
    void stopScanning() override;

    // Get the singleton instance
    static std::shared_ptr<HybridExternalScannerIOS> getInstance();

    // Called from Objective-C/Swift
    void handleKeyInput(const std::string& characters, int keyCode, bool isKeyDown);
    void updateDevices(const std::vector<DeviceInfo>& devices);

private:
    static std::shared_ptr<HybridExternalScannerIOS> _instance;
    static std::mutex _instanceMutex;

    void* _observer = nullptr; // Opaque pointer to Objective-C observer
};

} // namespace margelo::nitro::externalscanner
