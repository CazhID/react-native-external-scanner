#include "HybridExternalScanner_ios.hpp"
#include <iostream>

// Debug logging macro
#define ES_IOS_LOG(msg) std::cout << "[ExternalScanner iOS C++] " << msg << std::endl

namespace margelo::nitro::externalscanner {

std::shared_ptr<HybridExternalScannerIOS> HybridExternalScannerIOS::_instance = nullptr;
std::mutex HybridExternalScannerIOS::_instanceMutex;

HybridExternalScannerIOS::HybridExternalScannerIOS()
    : HybridObject(TAG), HybridExternalScanner() {
    ES_IOS_LOG("Constructor called");
}

HybridExternalScannerIOS::~HybridExternalScannerIOS() {
    ES_IOS_LOG("Destructor called");
    stopScanning();
}

std::shared_ptr<HybridExternalScannerIOS> HybridExternalScannerIOS::getInstance() {
    std::lock_guard<std::mutex> lock(_instanceMutex);
    if (!_instance) {
        ES_IOS_LOG("Creating new instance");
        _instance = std::make_shared<HybridExternalScannerIOS>();
    } else {
        ES_IOS_LOG("Returning existing instance");
    }
    return _instance;
}

bool HybridExternalScannerIOS::hasExternalScanner() {
    ES_IOS_LOG("hasExternalScanner called");
    return HybridExternalScanner::hasExternalScanner();
}

std::vector<DeviceInfo> HybridExternalScannerIOS::getConnectedDevices() {
    ES_IOS_LOG("getConnectedDevices called");
    return HybridExternalScanner::getConnectedDevices();
}

void HybridExternalScannerIOS::startScanning(
    const std::function<void(const ScanResult&)>& onScan,
    const std::optional<std::function<void(const std::string&, double)>>& onChar
) {
    ES_IOS_LOG("startScanning called");
    HybridExternalScanner::startScanning(onScan, onChar);
    // iOS observer setup is done in Objective-C
}

void HybridExternalScannerIOS::stopScanning() {
    ES_IOS_LOG("stopScanning called");
    HybridExternalScanner::stopScanning();
    // iOS observer cleanup is done in Objective-C
}

void HybridExternalScannerIOS::handleKeyInput(const std::string& characters, int keyCode, bool isKeyDown) {
    ES_IOS_LOG("handleKeyInput: chars='" << characters << "', keyCode=" << keyCode << ", isKeyDown=" << (isKeyDown ? "true" : "false"));

    if (!isKeyDown) {
        ES_IOS_LOG("handleKeyInput: Not key down, ignoring");
        return;
    }

    // isKeyDown is true, so action should be 0 (KEY_DOWN)
    int action = 0;
    ES_IOS_LOG("handleKeyInput: Forwarding to onKeyEvent with action=" << action);
    onKeyEvent(keyCode, action, characters, 0);
}

void HybridExternalScannerIOS::updateDevices(const std::vector<DeviceInfo>& devices) {
    ES_IOS_LOG("updateDevices: " << devices.size() << " devices");
    {
        std::lock_guard<std::mutex> lock(_devicesMutex);
        _connectedDevices = devices;
    }

    if (_connectionCallback) {
        ES_IOS_LOG("updateDevices: Calling connection callback");
        _connectionCallback(!devices.empty());
    }
}

} // namespace margelo::nitro::externalscanner
