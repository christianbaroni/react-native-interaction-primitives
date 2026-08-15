import * as React from 'react';
import { useEvent, useSharedValue, type ReanimatedEvent, type SharedValue } from 'react-native-reanimated';
import type { PagerProps, PagerRef, PagerScrollNativeEvent, PagerScrollPhase, PagerSetPageOptions } from './types';

type PagerWorkletEvent = ReanimatedEvent<PagerScrollNativeEvent>;

const PAGER_SCROLL_EVENT_NAMES = ['onPageScroll', 'topPageScroll'];

export type PagerController = Readonly<{
  offset: SharedValue<number>;
  onPageScroll: NonNullable<PagerProps['onPageScroll']>;
  page: SharedValue<number>;
  phase: SharedValue<PagerScrollPhase>;
  position: SharedValue<number>;
  ref: React.RefObject<PagerRef | null>;
  setPage(page: number, options?: PagerSetPageOptions): void;
}>;

export function usePager(): PagerController {
  const offset = useSharedValue(0);
  const page = useSharedValue(0);
  const phase = useSharedValue<PagerScrollPhase>('empty');
  const position = useSharedValue(0);
  const ref = React.useRef<PagerRef>(null);

  const setPage = React.useCallback((nextPage: number, options?: PagerSetPageOptions) => {
    ref.current?.setPage(nextPage, options);
  }, []);

  const onPageScroll = useEvent<PagerScrollNativeEvent>((event: PagerWorkletEvent) => {
    'worklet';
    offset.value = event.offset;
    page.value = event.page;
    phase.value = event.phase;
    position.value = event.position;
  }, PAGER_SCROLL_EVENT_NAMES);

  return React.useMemo(
    () => ({ offset, onPageScroll, page, phase, position, ref, setPage }),
    [offset, onPageScroll, page, phase, position, setPage]
  );
}
