import * as React from 'react';
import { useEvent, useSharedValue, type ReanimatedEvent, type SharedValue } from 'react-native-reanimated';
import type {
  PagerProps,
  PagerRef,
  PagerScrollNativeEvent,
  PagerScrollPhase,
  PagerSetPageOptions,
  SideDrawerCommandOptions,
  SideDrawerPhase,
  SideDrawerProgressNativeEvent,
  SideDrawerProps,
  SideDrawerRef,
} from './types';

type PagerWorkletEvent = ReanimatedEvent<PagerScrollNativeEvent>;
type SideDrawerWorkletEvent = ReanimatedEvent<SideDrawerProgressNativeEvent>;

const PAGER_SCROLL_EVENT_NAMES = ['onPageScroll', 'topPageScroll'];
const SIDE_DRAWER_PROGRESS_EVENT_NAMES = ['onProgress', 'topProgress'];

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

export type SideDrawerController = Readonly<{
  close(options?: SideDrawerCommandOptions): void;
  onProgress: NonNullable<SideDrawerProps['onProgress']>;
  open(options?: SideDrawerCommandOptions): void;
  phase: SharedValue<SideDrawerPhase>;
  progress: SharedValue<number>;
  ref: React.RefObject<SideDrawerRef | null>;
  settlingSource: SharedValue<'none' | 'programmatic' | 'release'>;
  targetOpen: SharedValue<boolean>;
  toggle(options?: SideDrawerCommandOptions): void;
}>;

export function useSideDrawer(): SideDrawerController {
  const progress = useSharedValue(0);
  const phase = useSharedValue<SideDrawerPhase>('closed');
  const settlingSource = useSharedValue<'none' | 'programmatic' | 'release'>('none');
  const targetOpen = useSharedValue(false);
  const ref = React.useRef<SideDrawerRef>(null);

  const close = React.useCallback((options?: SideDrawerCommandOptions) => ref.current?.close(options), []);
  const open = React.useCallback((options?: SideDrawerCommandOptions) => ref.current?.open(options), []);
  const toggle = React.useCallback((options?: SideDrawerCommandOptions) => ref.current?.toggle(options), []);

  const onProgress = useEvent<SideDrawerProgressNativeEvent>((event: SideDrawerWorkletEvent) => {
    'worklet';
    progress.value = event.progress;
    phase.value = event.phase;
    settlingSource.value = event.settlingSource;
    targetOpen.value = event.targetOpen;
  }, SIDE_DRAWER_PROGRESS_EVENT_NAMES);

  return React.useMemo(
    () => ({ close, onProgress, open, phase, progress, ref, settlingSource, targetOpen, toggle }),
    [close, onProgress, open, phase, progress, settlingSource, targetOpen, toggle]
  );
}
