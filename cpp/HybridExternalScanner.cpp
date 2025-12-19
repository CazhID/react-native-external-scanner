#include "HybridExternalScanner.hpp"
#include <algorithm>
#include <iostream>

// Debug logging macro
#define ES_CPP_LOG(msg) std::cout << "[ExternalScanner C++] " << msg << std::endl

namespace margelo::nitro::externalscanner {

HybridExternalScanner::HybridExternalScanner()
    : HybridObject(TAG), HybridExternalScannerSpec() {
    _lastKeyTime = std::chrono::steady_clock::now();
    ES_CPP_LOG("Constructor called");
}

HybridExternalScanner::~HybridExternalScanner() {
    ES_CPP_LOG("Destructor called");
    stopScanning();
}

bool HybridExternalScanner::hasExternalScanner() {
    std::lock_guard<std::mutex> lock(_devicesMutex);
    bool has = !_connectedDevices.empty();
    ES_CPP_LOG("hasExternalScanner: " << (has ? "true" : "false"));
    return has;
}

std::vector<DeviceInfo> HybridExternalScanner::getConnectedDevices() {
    std::lock_guard<std::mutex> lock(_devicesMutex);
    ES_CPP_LOG("getConnectedDevices: " << _connectedDevices.size() << " devices");
    return _connectedDevices;
}

void HybridExternalScanner::onScannerConnectionChanged(const std::function<void(bool)>& callback) {
    ES_CPP_LOG("onScannerConnectionChanged: callback registered");
    _connectionCallback = callback;
}

void HybridExternalScanner::startScanning(
    const std::function<void(const ScanResult&)>& onScan,
    const std::optional<std::function<void(const std::string&, double)>>& onChar
) {
    ES_CPP_LOG("startScanning called");
    _onScanCallback = onScan;
    _onCharCallback = onChar;
    _isScanning = true;
    clearBuffer();
    ES_CPP_LOG("startScanning: _isScanning = true, callback set: " << (onScan ? "yes" : "no"));
}

void HybridExternalScanner::stopScanning() {
    ES_CPP_LOG("stopScanning called");
    _isScanning = false;
    _onScanCallback = nullptr;
    _onCharCallback = std::nullopt;
    clearBuffer();
}

bool HybridExternalScanner::isScanning() {
    bool scanning = _isScanning.load();
    ES_CPP_LOG("isScanning: " << (scanning ? "true" : "false"));
    return scanning;
}

void HybridExternalScanner::setScanTimeout(double timeout) {
    ES_CPP_LOG("setScanTimeout: " << timeout);
    _scanTimeout = timeout;
}

void HybridExternalScanner::setMinScanLength(double length) {
    ES_CPP_LOG("setMinScanLength: " << length);
    _minScanLength = length;
}

void HybridExternalScanner::onKeyEvent(int keyCode, int action, const std::string& characters, int deviceId) {
    ES_CPP_LOG("onKeyEvent: keyCode=" << keyCode << ", action=" << action << ", chars='" << characters << "', deviceId=" << deviceId);

    if (!_isScanning) {
        ES_CPP_LOG("onKeyEvent: Not scanning, ignoring");
        return;
    }

    // action: 0 = KEY_DOWN, 1 = KEY_UP (we only process KEY_DOWN)
    if (action != 0) {
        ES_CPP_LOG("onKeyEvent: Not KEY_DOWN (action=" << action << "), ignoring");
        return;
    }

    auto now = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - _lastKeyTime).count();
    ES_CPP_LOG("onKeyEvent: elapsed since last key: " << elapsed << "ms, timeout: " << _scanTimeout << "ms");

    std::lock_guard<std::mutex> lock(_bufferMutex);

    // If too much time passed, clear the buffer (new scan)
    if (elapsed > _scanTimeout && !_scanBuffer.empty()) {
        ES_CPP_LOG("onKeyEvent: Timeout exceeded, processing buffer before new input");
        processBuffer();
    }

    _lastKeyTime = now;

    // Check for Enter key (end of scan)
    if (isEnterKey(keyCode)) {
        ES_CPP_LOG("onKeyEvent: Enter key detected, processing buffer");
        processBuffer();
        return;
    }

    // Add character to buffer
    if (!characters.empty()) {
        _scanBuffer += characters;
        ES_CPP_LOG("onKeyEvent: Added to buffer, current buffer: '" << _scanBuffer << "' (length: " << _scanBuffer.length() << ")");

        // Notify character callback if set
        if (_onCharCallback.has_value() && _onCharCallback.value()) {
            ES_CPP_LOG("onKeyEvent: Calling onChar callback");
            _onCharCallback.value()(characters, static_cast<double>(keyCode));
        }
    } else {
        ES_CPP_LOG("onKeyEvent: Empty characters, not adding to buffer");
    }
}

void HybridExternalScanner::onDeviceConnected(const DeviceInfo& device) {
    ES_CPP_LOG("onDeviceConnected: id=" << device.id << ", name=" << device.name);
    {
        std::lock_guard<std::mutex> lock(_devicesMutex);
        // Check if device already exists
        auto it = std::find_if(_connectedDevices.begin(), _connectedDevices.end(),
            [&device](const DeviceInfo& d) { return d.id == device.id; });

        if (it == _connectedDevices.end()) {
            _connectedDevices.push_back(device);
            ES_CPP_LOG("onDeviceConnected: Device added, total: " << _connectedDevices.size());
        } else {
            ES_CPP_LOG("onDeviceConnected: Device already exists");
        }
    }

    if (_connectionCallback) {
        ES_CPP_LOG("onDeviceConnected: Calling connection callback with true");
        _connectionCallback(true);
    }
}

void HybridExternalScanner::onDeviceDisconnected(int deviceId) {
    ES_CPP_LOG("onDeviceDisconnected: deviceId=" << deviceId);
    {
        std::lock_guard<std::mutex> lock(_devicesMutex);
        _connectedDevices.erase(
            std::remove_if(_connectedDevices.begin(), _connectedDevices.end(),
                [deviceId](const DeviceInfo& d) { return d.id == static_cast<double>(deviceId); }),
            _connectedDevices.end()
        );
        ES_CPP_LOG("onDeviceDisconnected: Remaining devices: " << _connectedDevices.size());
    }

    if (_connectionCallback) {
        std::lock_guard<std::mutex> lock(_devicesMutex);
        ES_CPP_LOG("onDeviceDisconnected: Calling connection callback");
        _connectionCallback(!_connectedDevices.empty());
    }
}

void HybridExternalScanner::processBuffer() {
    ES_CPP_LOG("processBuffer: buffer='" << _scanBuffer << "', length=" << _scanBuffer.length() << ", minLength=" << _minScanLength);

    if (_scanBuffer.length() >= static_cast<size_t>(_minScanLength)) {
        if (_onScanCallback) {
            auto now = std::chrono::system_clock::now();
            auto timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
                now.time_since_epoch()
            ).count();

            ScanResult result(_scanBuffer, static_cast<double>(timestamp));
            ES_CPP_LOG("processBuffer: Calling onScan callback with data='" << _scanBuffer << "'");
            _onScanCallback(result);
        } else {
            ES_CPP_LOG("processBuffer: ERROR - No onScan callback set!");
        }
    } else {
        ES_CPP_LOG("processBuffer: Buffer too short (" << _scanBuffer.length() << " < " << _minScanLength << "), not calling callback");
    }
    clearBuffer();
}

void HybridExternalScanner::clearBuffer() {
    ES_CPP_LOG("clearBuffer: Clearing buffer (was: '" << _scanBuffer << "')");
    _scanBuffer.clear();
}

bool HybridExternalScanner::isEnterKey(int keyCode) {
    // Android: KEYCODE_ENTER = 66, KEYCODE_NUMPAD_ENTER = 160
    // iOS GCKeyCode: ReturnOrEnter = 0x28 (40), KeypadEnter = 0x58 (88)
    bool isEnter = keyCode == 66 || keyCode == 160 || keyCode == 40 || keyCode == 88;
    ES_CPP_LOG("isEnterKey: keyCode=" << keyCode << " -> " << (isEnter ? "true" : "false"));
    return isEnter;
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
