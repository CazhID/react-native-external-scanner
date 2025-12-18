#import "ExternalScannerObserver.h"
#include "HybridExternalScanner_ios.hpp"
#include "DeviceInfo.hpp"
#include <vector>

using namespace margelo::nitro::externalscanner;

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
        _isMonitoring = NO;
        _connectedDevices = [NSMutableArray array];
        [self setupNotifications];
        [self checkConnectedDevices];
    }
    return self;
}

- (void)setupNotifications {
    // Monitor keyboard connection/disconnection
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidConnect:)
                                                 name:GCKeyboardDidConnectNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidDisconnect:)
                                                 name:GCKeyboardDidDisconnectNotification
                                               object:nil];

    // Also monitor for generic HID devices
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(controllerDidConnect:)
                                                 name:GCControllerDidConnectNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(controllerDidDisconnect:)
                                                 name:GCControllerDidDisconnectNotification
                                               object:nil];
}

- (void)checkConnectedDevices {
    [self.connectedDevices removeAllObjects];

    // Check for connected keyboards via GameController framework
    GCKeyboard *keyboard = [GCKeyboard coalescedKeyboard];
    if (keyboard) {
        [self.connectedDevices addObject:@{
            @"id": @(1),
            @"name": @"External Keyboard",
            @"vendorId": @(0),
            @"productId": @(0),
            @"isExternal": @YES
        }];
    }

    // Check for any connected controllers that might be scanners
    for (GCController *controller in [GCController controllers]) {
        if (controller.extendedGamepad == nil && controller.microGamepad == nil) {
            // Not a game controller, might be a scanner
            [self.connectedDevices addObject:@{
                @"id": @(controller.playerIndex + 100),
                @"name": controller.vendorName ?: @"Unknown Device",
                @"vendorId": @(0),
                @"productId": @(0),
                @"isExternal": @(controller.isAttachedToDevice == NO)
            }];
        }
    }

    [self syncDevicesToCpp];
}

- (void)syncDevicesToCpp {
    auto instance = HybridExternalScannerIOS::getInstance();
    if (!instance) return;

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

    instance->updateDevices(devices);
}

- (void)keyboardDidConnect:(NSNotification *)notification {
    [self checkConnectedDevices];
}

- (void)keyboardDidDisconnect:(NSNotification *)notification {
    [self checkConnectedDevices];
}

- (void)controllerDidConnect:(NSNotification *)notification {
    [self checkConnectedDevices];
}

- (void)controllerDidDisconnect:(NSNotification *)notification {
    [self checkConnectedDevices];
}

- (void)startMonitoring {
    if (self.isMonitoring) return;
    self.isMonitoring = YES;

    // Setup keyboard input handler
    GCKeyboard *keyboard = [GCKeyboard coalescedKeyboard];
    if (keyboard && keyboard.keyboardInput) {
        __weak __typeof__(self) weakSelf = self;
        keyboard.keyboardInput.keyChangedHandler = ^(GCKeyboardInput * _Nonnull keyboard,
                                                     GCControllerButtonInput * _Nonnull key,
                                                     GCKeyCode keyCode,
                                                     BOOL pressed) {
            [weakSelf handleKeyCode:keyCode pressed:pressed];
        };
    }
}

- (void)stopMonitoring {
    self.isMonitoring = NO;

    GCKeyboard *keyboard = [GCKeyboard coalescedKeyboard];
    if (keyboard && keyboard.keyboardInput) {
        keyboard.keyboardInput.keyChangedHandler = nil;
    }
}

- (void)handleKeyCode:(GCKeyCode)keyCode pressed:(BOOL)pressed {
    if (!self.isMonitoring) return;

    auto instance = HybridExternalScannerIOS::getInstance();
    if (!instance || !instance->isScanning()) return;

    // Convert GCKeyCode to character
    NSString *character = [self characterForKeyCode:keyCode];

    instance->handleKeyInput(
        character ? std::string([character UTF8String]) : "",
        (int)keyCode,
        pressed
    );
}

- (NSString *)characterForKeyCode:(GCKeyCode)keyCode {
    // Map common key codes to characters
    // Numbers 0-9 (GCKeyCode starts at 0x1E for '1' and 0x27 for '0')
    if (keyCode >= GCKeyCodeOne && keyCode <= GCKeyCodeNine) {
        return [NSString stringWithFormat:@"%c", (char)('1' + (keyCode - GCKeyCodeOne))];
    }
    if (keyCode == GCKeyCodeZero) {
        return @"0";
    }

    // Letters A-Z (GCKeyCode starts at 0x04 for 'A')
    if (keyCode >= GCKeyCodeKeyA && keyCode <= GCKeyCodeKeyZ) {
        return [NSString stringWithFormat:@"%c", (char)('A' + (keyCode - GCKeyCodeKeyA))];
    }

    // Special characters
    switch (keyCode) {
        case GCKeyCodeHyphen: return @"-";
        case GCKeyCodeEqualSign: return @"=";
        case GCKeyCodeOpenBracket: return @"[";
        case GCKeyCodeCloseBracket: return @"]";
        case GCKeyCodeBackslash: return @"\\";
        case GCKeyCodeSemicolon: return @";";
        case GCKeyCodeQuote: return @"'";
        case GCKeyCodeGraveAccentAndTilde: return @"`";
        case GCKeyCodeComma: return @",";
        case GCKeyCodePeriod: return @".";
        case GCKeyCodeSlash: return @"/";
        case GCKeyCodeSpacebar: return @" ";
        default: return nil;
    }
}

- (BOOL)hasExternalScanner {
    return self.connectedDevices.count > 0;
}

- (NSString *)getConnectedDevicesJson {
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self.connectedDevices
                                                       options:0
                                                         error:&error];
    if (error) {
        return @"[]";
    }
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopMonitoring];
}

@end
