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
    if (keyboard) {
        [self.connectedDevices addObject:@{
            @"id": @(1),
            @"name": @"External Keyboard",
            @"vendorId": @(0),
            @"productId": @(0),
            @"isExternal": @YES
        }];
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

- (void)startMonitoring {
    if (self.isMonitoring) return;
    self.isMonitoring = YES;

    // Setup GCKeyboard handler for key input
    [self setupGCKeyboardHandler];
}

- (void)setupGCKeyboardHandler {
    GCKeyboard *keyboard = [GCKeyboard coalescedKeyboard];
    if (keyboard && keyboard.keyboardInput) {
        __weak __typeof__(self) weakSelf = self;
        keyboard.keyboardInput.keyChangedHandler = ^(GCKeyboardInput * _Nonnull keyboardInput,
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

- (void)handleTextInput:(NSString *)text {
    if (!self.isMonitoring) return;

    auto instance = HybridExternalScannerIOS::getInstance();
    if (!instance || !instance->isScanning()) return;

    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        NSString *charStr = [NSString stringWithCharacters:&c length:1];

        instance->handleKeyInput(
            std::string([charStr UTF8String]),
            0,
            true
        );
    }
}

- (void)handleEnterKey {
    if (!self.isMonitoring) return;

    auto instance = HybridExternalScannerIOS::getInstance();
    if (!instance || !instance->isScanning()) return;

    // Send enter key (key code 40 = GCKeyCodeReturnOrEnter)
    instance->handleKeyInput("", 40, true);
}

- (void)handleKeyCode:(GCKeyCode)keyCode pressed:(BOOL)pressed {
    if (!self.isMonitoring) return;
    if (!pressed) return; // Only handle key down

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
    // Check for Enter/Return keys first
    if (keyCode == GCKeyCodeReturnOrEnter || keyCode == GCKeyCodeKeypadEnter) {
        return nil; // Return nil so it triggers buffer processing via empty string + enter keycode
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

    return nil;
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
