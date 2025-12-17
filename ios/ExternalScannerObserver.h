#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <GameController/GameController.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * ExternalScannerObserver
 * Monitors for external keyboard/scanner devices and intercepts their input
 */
@interface ExternalScannerObserver : NSObject

+ (instancetype)sharedInstance;

/// Start monitoring for external scanner input
- (void)startMonitoring;

/// Stop monitoring
- (void)stopMonitoring;

/// Check if any external keyboard/scanner is connected
- (BOOL)hasExternalScanner;

/// Get list of connected external devices as JSON
- (NSString *)getConnectedDevicesJson;

@end

NS_ASSUME_NONNULL_END
