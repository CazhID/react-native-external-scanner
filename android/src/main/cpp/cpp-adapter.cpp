#include <jni.h>
#include <fbjni/fbjni.h>
#include <NitroModules/HybridObjectRegistry.hpp>
#include "NitroExternalScannerOnLoad.hpp"
#include "HybridExternalScanner_android.hpp"

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  using namespace margelo::nitro;
  using namespace margelo::nitro::externalscanner;

  // Store JVM reference for later use
  HybridExternalScannerAndroid::_jvm = vm;

  return facebook::jni::initialize(vm, [] {
    // Register the ExternalScanner HybridObject
    HybridObjectRegistry::registerHybridObjectConstructor(
      "ExternalScanner",
      []() -> std::shared_ptr<HybridObject> {
        return HybridExternalScannerAndroid::getInstance();
      }
    );
  });
}
