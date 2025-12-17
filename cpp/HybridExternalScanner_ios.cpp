#include "HybridExternalScanner_ios.hpp"

namespace margelo::nitro::externalscanner {

std::shared_ptr<HybridExternalScannerIOS> HybridExternalScannerIOS::_instance = nullptr;
std::mutex HybridExternalScannerIOS::_instanceMutex;

HybridExternalScannerIOS::HybridExternalScannerIOS()
    : HybridObject(TAG), HybridExternalScanner() {
}

HybridExternalScannerIOS::~HybridExternalScannerIOS() {
    stopScanning();
}

std::shared_ptr<HybridExternalScannerIOS> HybridExternalScannerIOS::getInstance() {
    std::lock_guard<std::mutex> lock(_instanceMutex);
    if (!_instance) {
        _instance = std::make_shared<HybridExternalScannerIOS>();
    }
    return _instance;
}

bool HybridExternalScannerIOS::hasExternalScanner() {
    // Will be populated by the iOS observer
    return HybridExternalScanner::hasExternalScanner();
}

std::vector<DeviceInfo> HybridExternalScannerIOS::getConnectedDevices() {
    return HybridExternalScanner::getConnectedDevices();
}

void HybridExternalScannerIOS::startScanning(
    const std::function<void(const ScanResult&)>& onScan,
    const std::optional<std::function<void(const std::string&, double)>>& onChar
) {
    HybridExternalScanner::startScanning(onScan, onChar);
    // iOS observer setup is done in Objective-C
}

void HybridExternalScannerIOS::stopScanning() {
    HybridExternalScanner::stopScanning();
    // iOS observer cleanup is done in Objective-C
}

void HybridExternalScannerIOS::handleKeyInput(const std::string& characters, int keyCode, bool isKeyDown) {
    if (!isKeyDown) return;
    onKeyEvent(keyCode, isKeyDown ? 0 : 1, characters, 0);
}

void HybridExternalScannerIOS::updateDevices(const std::vector<DeviceInfo>& devices) {
    {
        std::lock_guard<std::mutex> lock(_devicesMutex);
        _connectedDevices = devices;
    }

    if (_connectionCallback) {
        _connectionCallback(!devices.empty());
    }
}

} // namespace margelo::nitro::externalscanner
