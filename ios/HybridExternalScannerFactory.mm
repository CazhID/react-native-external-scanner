#import <Foundation/Foundation.h>
#include <NitroModules/HybridObjectRegistry.hpp>
#include "HybridExternalScanner_ios.hpp"
#include "ExternalScannerObserver.h"

using namespace margelo::nitro;
using namespace margelo::nitro::externalscanner;

@interface ExternalScannerRegistration : NSObject
@end

@implementation ExternalScannerRegistration

+ (void)load {
    // Register the HybridObject when the module loads
    HybridObjectRegistry::registerHybridObjectConstructor(
        "ExternalScanner",
        []() -> std::shared_ptr<HybridObject> {
            // Initialize the observer
            [[ExternalScannerObserver sharedInstance] startMonitoring];
            return HybridExternalScannerIOS::getInstance();
        }
    );
}

@end
