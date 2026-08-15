import type { PagerPhase, PagerScrollPhase, PagerState } from './types';
import type { NativePagerState } from './specs/RNPagerViewNativeComponent';

export type PagerTargetInput = Readonly<{
  anchorPage: number;
  naturalTargetOffset: number;
  pageCount: number;
  pageExtent: number;
}>;

function clampPage(page: number, pageCount: number): number {
  if (pageCount <= 0) return 0;
  return Math.min(pageCount - 1, Math.max(0, page));
}

function roundedPage(value: number, pageCount: number): number {
  return clampPage(Math.round(value), pageCount);
}

function settlingSource(value: NativePagerState['settlingSource']): 'programmatic' | 'release' {
  if (value === 'programmatic' || value === 'release') return value;
  throw new Error('Pager entered the settling phase without a settling source.');
}

export function resolveBoundedPagerTarget(input: PagerTargetInput): number {
  if (input.pageCount <= 0) return 0;

  const anchorPage = roundedPage(input.anchorPage, input.pageCount);
  if (input.pageExtent <= 0) return anchorPage;

  const projectedPage = roundedPage(input.naturalTargetOffset / input.pageExtent, input.pageCount);
  return clampPage(Math.min(anchorPage + 1, Math.max(anchorPage - 1, projectedPage)), input.pageCount);
}

export function rehydratePagerState(native: NativePagerState): PagerState {
  const phaseKind: PagerScrollPhase = native.phase;
  let phase: PagerPhase;
  if (native.pageCount <= 0 || phaseKind === 'empty') {
    phase = { kind: 'empty' };
  } else if (phaseKind === 'dragging') {
    phase = { anchorOffset: native.anchorOffset, anchorPage: native.anchorPage, kind: 'dragging' };
  } else if (phaseKind === 'settling') {
    phase = {
      anchorPage: native.anchorPage,
      kind: 'settling',
      source: settlingSource(native.settlingSource),
      targetPage: native.targetPage,
    };
  } else {
    phase = { kind: 'idle', page: native.page };
  }

  return {
    offset: native.offset,
    pageCount: native.pageCount,
    pageExtent: native.pageExtent,
    phase,
    position: native.position,
  };
}
