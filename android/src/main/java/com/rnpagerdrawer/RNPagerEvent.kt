package com.rnpagerdrawer

import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.events.Event

internal class RNPagerEvent(
    surfaceId: Int,
    viewTag: Int,
    private val name: String,
    private val payload: WritableMap,
    private val coalesces: Boolean,
) : Event<RNPagerEvent>(surfaceId, viewTag) {
    override fun getEventName(): String = name

    override fun canCoalesce(): Boolean = coalesces

    override fun getEventData(): WritableMap = payload
}
