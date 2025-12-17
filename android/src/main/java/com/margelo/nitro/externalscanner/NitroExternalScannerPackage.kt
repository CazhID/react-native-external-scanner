package com.margelo.nitro.externalscanner

import android.content.Context
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfoProvider
import com.facebook.react.BaseReactPackage

class NitroExternalScannerPackage : BaseReactPackage() {
    override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? {
        // Initialize on first module request
        initializeIfNeeded(reactContext.applicationContext)
        return null
    }

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider = ReactModuleInfoProvider { HashMap() }

    companion object {
        @Volatile
        private var isInitialized = false

        init {
            NitroExternalScannerOnLoad.initializeNative()
        }

        @Synchronized
        fun initializeIfNeeded(context: Context) {
            if (!isInitialized) {
                ExternalScannerUtil.init(context)
                isInitialized = true
            }
        }

        /**
         * Call this from your Application.onCreate() or MainActivity.onCreate()
         * to ensure early initialization
         */
        @JvmStatic
        fun initialize(context: Context) {
            initializeIfNeeded(context.applicationContext)
        }
    }
}
