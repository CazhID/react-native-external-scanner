package com.margelo.nitro.externalscanner

import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfoProvider
import com.facebook.react.BaseReactPackage

class NitroExternalScannerPackage : BaseReactPackage() {
    override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? {
        // Initialize the ExternalScannerUtil with the application context
        ExternalScannerUtil.init(reactContext.applicationContext)
        return null
    }

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider = ReactModuleInfoProvider { HashMap() }

    companion object {
        init {
            NitroExternalScannerOnLoad.initializeNative()
        }
    }
}
