#import "ExternalScannerObserver.h"
#include "HybridExternalScanner_ios.hpp"
#include "DeviceInfo.hpp"
#include <vector>

using namespace margelo::nitro::externalscanner;

#define LOG_TAG @"[ExternalScanner]"
#define ES_LOG(fmt, ...) NSLog(@"%@ " fmt, LOG_TAG, ##__VA_ARGS__)

@interface ExternalScannerObserver ()

@property (nonatomic, assign) BOOL isMonitoring;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *connectedDevices;

@end

@implementation ExternalScannerObserver

+ (instancetype)sharedInstance {
    static ExternalScannerObserver *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ExternalScannerObserver alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        ES_LOG(@"init - Initializing ExternalScannerObserver");
        _isMonitoring = NO;
        _connectedDevices = [NSMutableArray array];
        [self setupNotifications];
        [self checkConnectedDevices];
    }
    return self;
}

- (void)setupNotifications {
    ES_LOG(@"setupNotifications - Registering for keyboard notifications");

    // Monitor keyboard connection/disconnection via GameController
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidConnect:)
                                                 name:GCKeyboardDidConnectNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidDisconnect:)
                                                 name:GCKeyboardDidDisconnectNotification
                                               object:nil];
}

- (void)checkConnectedDevices {
    [self.connectedDevices removeAllObjects];

    // Check for connected keyboards via GameController framework
    GCKeyboard *keyboard = [GCKeyboard coalescedKeyboard];
    ES_LOG(@"checkConnectedDevices - GCKeyboard coalescedKeyboard: %@", keyboard ? @"FOUND" : @"NOT FOUND");

    if (keyboard) {
        ES_LOG(@"checkConnectedDevices - Keyboard input available: %@", keyboard.keyboardInput ? @"YES" : @"NO");
        [self.connectedDevices addObject:@{
            @"id": @(1),
            @"name": @"External Keyboard",
            @"vendorId": @(0),
            @"productId": @(0),
            @"isExternal": @YES
        }];
    }

    ES_LOG(@"checkConnectedDevices - Total devices found: %lu", (unsigned long)self.connectedDevices.count);
    [self syncDevicesToCpp];
}

- (void)syncDevicesToCpp {
    auto instance = HybridExternalScannerIOS::getInstance();
    if (!instance) {
        ES_LOG(@"syncDevicesToCpp - ERROR: HybridExternalScannerIOS instance is null");
        return;
    }

    std::vector<DeviceInfo> devices;
    for (NSDictionary *device in self.connectedDevices) {
        DeviceInfo info(
            [device[@"id"] doubleValue],
            std::string([device[@"name"] UTF8String]),
            [device[@"vendorId"] doubleValue],
            [device[@"productId"] doubleValue],
            [device[@"isExternal"] boolValue]
        );
        devices.push_back(info);
    }

    ES_LOG(@"syncDevicesToCpp - Syncing %lu devices to C++", (unsigned long)devices.size());
    instance->updateDevices(devices);
}

- (void)keyboardDidConnect:(NSNotification *)notification {
    ES_LOG(@"keyboardDidConnect - Keyboard connected notification received");
    [self checkConnectedDevices];

    // Re-setup handler if we're monitoring
    if (self.isMonitoring) {
        ES_LOG(@"keyboardDidConnect - Re-setting up keyboard handler");
        [self setupGCKeyboardHandler];
    }
}

- (void)keyboardDidDisconnect:(NSNotification *)notification {
    ES_LOG(@"keyboardDidDisconnect - Keyboard disconnected notification received");
    [self checkConnectedDevices];
}

- (void)startMonitoring {
    ES_LOG(@"startMonitoring - Called, isMonitoring: %@", self.isMonitoring ? @"YES" : @"NO");

    if (self.isMonitoring) {
        ES_LOG(@"startMonitoring - Already monitoring, skipping");
        return;
    }
    self.isMonitoring = YES;

    // Setup GCKeyboard handler for key input
    [self setupGCKeyboardHandler];

    ES_LOG(@"startMonitoring - Monitoring started");
}

- (void)setupGCKeyboardHandler {
    GCKeyboard *keyboard = [GCKeyboard coalescedKeyboard];
    ES_LOG(@"setupGCKeyboardHandler - GCKeyboard: %@", keyboard ? @"FOUND" : @"NOT FOUND");

    if (keyboard && keyboard.keyboardInput) {
        ES_LOG(@"setupGCKeyboardHandler - Setting up keyChangedHandler");
        __weak __typeof__(self) weakSelf = self;
        keyboard.keyboardInput.keyChangedHandler = ^(GCKeyboardInput * _Nonnull keyboardInput,
                                                     GCControllerButtonInput * _Nonnull key,
                                                     GCKeyCode keyCode,
                                                     BOOL pressed) {
            ES_LOG(@"keyChangedHandler - keyCode: %ld, pressed: %@", (long)keyCode, pressed ? @"YES" : @"NO");
            [weakSelf handleKeyCode:keyCode pressed:pressed];
        };
        ES_LOG(@"setupGCKeyboardHandler - Handler set successfully");
    } else {
        ES_LOG(@"setupGCKeyboardHandler - ERROR: No keyboard or keyboardInput available");
    }
}

- (void)stopMonitoring {
    ES_LOG(@"stopMonitoring - Called");
    self.isMonitoring = NO;

    GCKeyboard *keyboard = [GCKeyboard coalescedKeyboard];
    if (keyboard && keyboard.keyboardInput) {
        keyboard.keyboardInput.keyChangedHandler = nil;
        ES_LOG(@"stopMonitoring - Handler cleared");
    }
}

- (void)handleTextInput:(NSString *)text {
    ES_LOG(@"handleTextInput - text: '%@', isMonitoring: %@", text, self.isMonitoring ? @"YES" : @"NO");

    if (!self.isMonitoring) {
        ES_LOG(@"handleTextInput - Not monitoring, ignoring");
        return;
    }

    auto instance = HybridExternalScannerIOS::getInstance();
    if (!instance) {
        ES_LOG(@"handleTextInput - ERROR: Instance is null");
        return;
    }

    if (!instance->isScanning()) {
        ES_LOG(@"handleTextInput - Not scanning, ignoring");
        return;
    }

    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        NSString *charStr = [NSString stringWithCharacters:&c length:1];

        ES_LOG(@"handleTextInput - Sending char: '%@'", charStr);
        instance->handleKeyInput(
            std::string([charStr UTF8String]),
            0,
            true
        );
    }
}

- (void)handleEnterKey {
    ES_LOG(@"handleEnterKey - Called, isMonitoring: %@", self.isMonitoring ? @"YES" : @"NO");

    if (!self.isMonitoring) return;

    auto instance = HybridExternalScannerIOS::getInstance();
    if (!instance || !instance->isScanning()) {
        ES_LOG(@"handleEnterKey - Instance null or not scanning");
        return;
    }

    ES_LOG(@"handleEnterKey - Sending enter key");
    instance->handleKeyInput("", 40, true);
}

- (void)handleKeyCode:(GCKeyCode)keyCode pressed:(BOOL)pressed {
    ES_LOG(@"handleKeyCode - keyCode: %ld, pressed: %@, isMonitoring: %@",
           (long)keyCode, pressed ? @"YES" : @"NO", self.isMonitoring ? @"YES" : @"NO");

    if (!self.isMonitoring) {
        ES_LOG(@"handleKeyCode - Not monitoring, ignoring");
        return;
    }

    if (!pressed) {
        ES_LOG(@"handleKeyCode - Key up event, ignoring");
        return;
    }

    auto instance = HybridExternalScannerIOS::getInstance();
    if (!instance) {
        ES_LOG(@"handleKeyCode - ERROR: Instance is null");
        return;
    }

    bool isScanning = instance->isScanning();
    ES_LOG(@"handleKeyCode - isScanning: %@", isScanning ? @"YES" : @"NO");

    if (!isScanning) {
        ES_LOG(@"handleKeyCode - Not scanning, ignoring");
        return;
    }

    // Convert GCKeyCode to character
    NSString *character = [self characterForKeyCode:keyCode];
    ES_LOG(@"handleKeyCode - Mapped character: '%@'", character ?: @"(nil/enter)");

    std::string charStr = character ? std::string([character UTF8String]) : "";
    ES_LOG(@"handleKeyCode - Sending to C++: char='%s', keyCode=%ld", charStr.c_str(), (long)keyCode);

    instance->handleKeyInput(charStr, (int)keyCode, pressed);
}

- (NSString *)characterForKeyCode:(GCKeyCode)keyCode {
    // Check for Enter/Return keys first
    if (keyCode == GCKeyCodeReturnOrEnter || keyCode == GCKeyCodeKeypadEnter) {
        ES_LOG(@"characterForKeyCode - Enter key detected (keyCode: %ld)", (long)keyCode);
        return nil;
    }

    // Numbers 0-9
    if (keyCode >= GCKeyCodeOne && keyCode <= GCKeyCodeNine) {
        return [NSString stringWithFormat:@"%c", (char)('1' + (keyCode - GCKeyCodeOne))];
    }
    if (keyCode == GCKeyCodeZero) {
        return @"0";
    }

    // Letters A-Z
    if (keyCode >= GCKeyCodeKeyA && keyCode <= GCKeyCodeKeyZ) {
        return [NSString stringWithFormat:@"%c", (char)('A' + (keyCode - GCKeyCodeKeyA))];
    }

    // Special characters
    if (keyCode == GCKeyCodeHyphen) return @"-";
    if (keyCode == GCKeyCodeEqualSign) return @"=";
    if (keyCode == GCKeyCodeOpenBracket) return @"[";
    if (keyCode == GCKeyCodeCloseBracket) return @"]";
    if (keyCode == GCKeyCodeBackslash) return @"\\";
    if (keyCode == GCKeyCodeSemicolon) return @";";
    if (keyCode == GCKeyCodeQuote) return @"'";
    if (keyCode == GCKeyCodeGraveAccentAndTilde) return @"`";
    if (keyCode == GCKeyCodeComma) return @",";
    if (keyCode == GCKeyCodePeriod) return @".";
    if (keyCode == GCKeyCodeSlash) return @"/";
    if (keyCode == GCKeyCodeSpacebar) return @" ";

    ES_LOG(@"characterForKeyCode - Unknown keyCode: %ld", (long)keyCode);
    return nil;
}

- (BOOL)hasExternalScanner {
    BOOL has = self.connectedDevices.count > 0;
    ES_LOG(@"hasExternalScanner - %@", has ? @"YES" : @"NO");
    return has;
}

- (NSString *)getConnectedDevicesJson {
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self.connectedDevices
                                                       options:0
                                                         error:&error];
    if (error) {
        ES_LOG(@"getConnectedDevicesJson - Error: %@", error);
        return @"[]";
    }
    NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    ES_LOG(@"getConnectedDevicesJson - %@", json);
    return json;
}

- (void)dealloc {
    ES_LOG(@"dealloc - Cleaning up");
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopMonitoring];
}

@end
