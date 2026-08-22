package com.rninteractionprimitives

import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.events.Event

internal class RNDirectEvent(
    surfaceId: Int,
    viewTag: Int,
    private val name: String,
    private val payload: WritableMap,
    private val coalesces: Boolean,
) : Event<RNDirectEvent>(surfaceId, viewTag) {
    override fun getEventName(): String = name

    override fun canCoalesce(): Boolean = coalesces

    override fun getEventData(): WritableMap = payload
}
