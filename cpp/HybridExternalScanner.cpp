#include "HybridExternalScanner.hpp"
#include <algorithm>

namespace margelo::nitro::externalscanner {

HybridExternalScanner::HybridExternalScanner() : HybridObject(TAG) {
    _lastKeyTime = std::chrono::steady_clock::now();
}

HybridExternalScanner::~HybridExternalScanner() {
    stopScanning();
}

bool HybridExternalScanner::hasExternalScanner() {
    std::lock_guard<std::mutex> lock(_devicesMutex);
    return !_connectedDevices.empty();
}

std::vector<DeviceInfo> HybridExternalScanner::getConnectedDevices() {
    std::lock_guard<std::mutex> lock(_devicesMutex);
    return _connectedDevices;
}

void HybridExternalScanner::onScannerConnectionChanged(const std::function<void(bool)>& callback) {
    _connectionCallback = callback;
}

void HybridExternalScanner::startScanning(
    const std::function<void(const ScanResult&)>& onScan,
    const std::optional<std::function<void(const std::string&, double)>>& onChar
) {
    _onScanCallback = onScan;
    _onCharCallback = onChar;
    _isScanning = true;
    clearBuffer();
}

void HybridExternalScanner::stopScanning() {
    _isScanning = false;
    _onScanCallback = nullptr;
    _onCharCallback = std::nullopt;
    clearBuffer();
}

bool HybridExternalScanner::isScanning() {
    return _isScanning.load();
}

void HybridExternalScanner::setScanTimeout(double timeout) {
    _scanTimeout = timeout;
}

void HybridExternalScanner::setMinScanLength(double length) {
    _minScanLength = length;
}

void HybridExternalScanner::onKeyEvent(int keyCode, int action, const std::string& characters, int deviceId) {
    if (!_isScanning) {
        return;
    }

    // action: 0 = KEY_DOWN, 1 = KEY_UP (we only process KEY_DOWN)
    if (action != 0) {
        return;
    }

    auto now = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - _lastKeyTime).count();

    std::lock_guard<std::mutex> lock(_bufferMutex);

    // If too much time passed, clear the buffer (new scan)
    if (elapsed > _scanTimeout && !_scanBuffer.empty()) {
        processBuffer();
    }

    _lastKeyTime = now;

    // Check for Enter key (end of scan)
    if (isEnterKey(keyCode)) {
        processBuffer();
        return;
    }

    // Add character to buffer
    if (!characters.empty()) {
        _scanBuffer += characters;

        // Notify character callback if set
        if (_onCharCallback.has_value() && _onCharCallback.value()) {
            _onCharCallback.value()(characters, static_cast<double>(keyCode));
        }
    }
}

void HybridExternalScanner::onDeviceConnected(const DeviceInfo& device) {
    {
        std::lock_guard<std::mutex> lock(_devicesMutex);
        // Check if device already exists
        auto it = std::find_if(_connectedDevices.begin(), _connectedDevices.end(),
            [&device](const DeviceInfo& d) { return d.id == device.id; });

        if (it == _connectedDevices.end()) {
            _connectedDevices.push_back(device);
        }
    }

    if (_connectionCallback) {
        _connectionCallback(true);
    }
}

void HybridExternalScanner::onDeviceDisconnected(int deviceId) {
    {
        std::lock_guard<std::mutex> lock(_devicesMutex);
        _connectedDevices.erase(
            std::remove_if(_connectedDevices.begin(), _connectedDevices.end(),
                [deviceId](const DeviceInfo& d) { return d.id == static_cast<double>(deviceId); }),
            _connectedDevices.end()
        );
    }

    if (_connectionCallback) {
        std::lock_guard<std::mutex> lock(_devicesMutex);
        _connectionCallback(!_connectedDevices.empty());
    }
}

void HybridExternalScanner::processBuffer() {
    if (_scanBuffer.length() >= static_cast<size_t>(_minScanLength)) {
        if (_onScanCallback) {
            auto now = std::chrono::system_clock::now();
            auto timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
                now.time_since_epoch()
            ).count();

            ScanResult result(_scanBuffer, static_cast<double>(timestamp));
            _onScanCallback(result);
        }
    }
    clearBuffer();
}

void HybridExternalScanner::clearBuffer() {
    _scanBuffer.clear();
}

bool HybridExternalScanner::isEnterKey(int keyCode) {
    // Android: KEYCODE_ENTER = 66, KEYCODE_NUMPAD_ENTER = 160
    // iOS: UIKeyboardHIDUsageKeyboardReturnOrEnter = 0x28 (40)
    return keyCode == 66 || keyCode == 160 || keyCode == 40 || keyCode == 0x28;
}

std::string HybridExternalScanner::keyCodeToChar(int keyCode, bool shiftPressed) {
    // This is a fallback - platforms should provide the character directly
    // Android keycodes for 0-9: 7-16, A-Z: 29-54
    if (keyCode >= 7 && keyCode <= 16) {
        return std::string(1, '0' + (keyCode - 7));
    }
    if (keyCode >= 29 && keyCode <= 54) {
        char c = 'a' + (keyCode - 29);
        if (shiftPressed) {
            c = std::toupper(c);
        }
        return std::string(1, c);
    }
    return "";
}

} // namespace margelo::nitro::externalscanner
