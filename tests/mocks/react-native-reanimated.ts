import * as React from 'react';

export function useSharedValue<T>(value: T) {
  return React.useRef({ value }).current;
}

export type ReanimatedEvent<Event extends object> = { eventName: string } & (Event extends { nativeEvent: infer NativeEvent extends object }
  ? NativeEvent
  : Event);

export function useEvent<Event extends object, Context extends Record<string, unknown> = never>(
  handler: (event: ReanimatedEvent<Event>, context?: Context) => void
): (event: Event, context?: Context) => void;
export function useEvent<Context extends Record<string, unknown> = never>(handler: (event: object, context?: Context) => void) {
  return (event: object, context?: Context) => {
    const nativeEvent =
      'nativeEvent' in event && typeof event.nativeEvent === 'object' && event.nativeEvent !== null ? event.nativeEvent : event;
    handler({ ...nativeEvent, eventName: 'onPageScroll' }, context);
  };
}

export type SharedValue<T> = { value: T };
