package com.rninteractionprimitives

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.ModuleSpec
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfoProvider

class RNInteractionPrimitivesPackage : BaseReactPackage() {
    override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? = null

    override fun getViewManagers(reactContext: ReactApplicationContext): List<ModuleSpec> {
        return listOf(
            ModuleSpec.viewManagerSpec { RNPagerPageViewManager() },
            ModuleSpec.viewManagerSpec { RNPagerViewManager() },
            ModuleSpec.viewManagerSpec { RNSideDrawerPanelViewManager() },
            ModuleSpec.viewManagerSpec { RNSideDrawerContentViewManager() },
            ModuleSpec.viewManagerSpec { RNSideDrawerViewManager() },
        )
    }

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider = ReactModuleInfoProvider(::emptyMap)
}
