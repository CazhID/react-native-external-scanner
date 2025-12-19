#import "ExternalScannerObserver.h"
#include "HybridExternalScanner_ios.hpp"
#include "DeviceInfo.hpp"
#include <vector>

using namespace margelo::nitro::externalscanner;

// Hidden text field for capturing scanner input
@interface ScannerTextField : UITextField <UITextFieldDelegate>
@property (nonatomic, weak) ExternalScannerObserver *observer;
@end

@implementation ScannerTextField

- (instancetype)init {
    self = [super init];
    if (self) {
        self.delegate = self;
        self.autocorrectionType = UITextAutocorrectionTypeNo;
        self.autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.spellCheckingType = UITextSpellCheckingTypeNo;
        self.keyboardType = UIKeyboardTypeASCIICapable;
        self.returnKeyType = UIReturnKeyDone;
        // Make invisible but still functional
        self.frame = CGRectMake(-1000, -1000, 1, 1);
        self.alpha = 0.01;
    }
    return self;
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

// Prevent the keyboard from showing
- (UIView *)inputView {
    return [[UIView alloc] initWithFrame:CGRectZero];
}

// Prevent the accessory view from showing
- (UIView *)inputAccessoryView {
    return nil;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (self.observer) {
        [self.observer handleTextInput:string];
    }
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (self.observer) {
        [self.observer handleEnterKey];
    }
    // Clear after processing
    textField.text = @"";
    return NO;
}

@end

@interface ExternalScannerObserver ()

@property (nonatomic, assign) BOOL isMonitoring;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *connectedDevices;
@property (nonatomic, strong) ScannerTextField *hiddenTextField;
@property (nonatomic, strong) NSTimer *focusTimer;

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

    // Monitor for external keyboard notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(externalKeyboardDidConnect:)
                                                 name:UIKeyboardDidShowNotification
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

- (void)externalKeyboardDidConnect:(NSNotification *)notification {
    [self checkConnectedDevices];
}

- (void)startMonitoring {
    if (self.isMonitoring) return;
    self.isMonitoring = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        // Create hidden text field if needed
        if (!self.hiddenTextField) {
            self.hiddenTextField = [[ScannerTextField alloc] init];
            self.hiddenTextField.observer = self;
        }

        // Add to key window
        UIWindow *keyWindow = [self getKeyWindow];
        if (keyWindow) {
            [keyWindow addSubview:self.hiddenTextField];
            [self.hiddenTextField becomeFirstResponder];
        }

        // Setup GCKeyboard handler as backup
        [self setupGCKeyboardHandler];

        // Start timer to maintain focus
        [self startFocusTimer];
    });
}

- (UIWindow *)getKeyWindow {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) {
                    return window;
                }
            }
        }
    }
    return nil;
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

- (void)startFocusTimer {
    [self.focusTimer invalidate];
    __weak __typeof__(self) weakSelf = self;
    self.focusTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                      repeats:YES
                                                        block:^(NSTimer * _Nonnull timer) {
        [weakSelf maintainFocus];
    }];
}

- (void)maintainFocus {
    if (!self.isMonitoring) return;

    auto instance = HybridExternalScannerIOS::getInstance();
    if (!instance || !instance->isScanning()) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.hiddenTextField && ![self.hiddenTextField isFirstResponder]) {
            [self.hiddenTextField becomeFirstResponder];
        }
    });
}

- (void)stopMonitoring {
    self.isMonitoring = NO;

    [self.focusTimer invalidate];
    self.focusTimer = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.hiddenTextField resignFirstResponder];
        [self.hiddenTextField removeFromSuperview];
    });

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

        // Use a generic key code for text input (actual character is what matters)
        instance->handleKeyInput(
            std::string([charStr UTF8String]),
            0, // Key code not available via text input
            true // isKeyDown
        );
    }
}

- (void)handleEnterKey {
    if (!self.isMonitoring) return;

    auto instance = HybridExternalScannerIOS::getInstance();
    if (!instance || !instance->isScanning()) return;

    // Send enter key (key code 40 = GCKeyCodeReturnOrEnter)
    instance->handleKeyInput("", 40, true);

    // Clear the text field
    dispatch_async(dispatch_get_main_queue(), ^{
        self.hiddenTextField.text = @"";
    });
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
