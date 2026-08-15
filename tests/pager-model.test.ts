import { describe, expect, it } from 'vitest';
import { rehydratePagerState, resolveBoundedPagerTarget } from '../src/pagerModel';
import type { NativePagerState } from '../src/specs/RNPagerViewNativeComponent';

const pageExtent = 320;

function target(overrides: Partial<Parameters<typeof resolveBoundedPagerTarget>[0]> = {}) {
  return resolveBoundedPagerTarget({
    anchorPage: 2,
    naturalTargetOffset: pageExtent * 2,
    pageCount: 5,
    pageExtent,
    ...overrides,
  });
}

function nativeState(overrides: Partial<NativePagerState> = {}): NativePagerState {
  return {
    anchorOffset: 0,
    anchorPage: 0,
    offset: 0,
    page: 0,
    pageCount: 5,
    pageExtent,
    phase: 'idle',
    position: 0,
    settlingSource: 'none',
    targetPage: -1,
    ...overrides,
  };
}

describe('Pager model', () => {
  it('bounds one release to the page adjacent to its committed anchor', () => {
    expect(target({ naturalTargetOffset: pageExtent * 4 })).toBe(3);
    expect(target({ naturalTargetOffset: 0 })).toBe(1);
  });

  it('uses the platform projection crossing instead of a second distance threshold', () => {
    expect(target({ naturalTargetOffset: pageExtent * 2.49 })).toBe(2);
    expect(target({ naturalTargetOffset: pageExtent * 2.5 })).toBe(3);
    expect(target({ naturalTargetOffset: pageExtent * 1.51 })).toBe(2);
    expect(target({ naturalTargetOffset: pageExtent * 1.49 })).toBe(1);
  });

  it('anchors an interrupted release to the committed in-flight target', () => {
    expect(target({ anchorPage: 1, naturalTargetOffset: pageExtent * 1.55 })).toBe(2);
    expect(target({ anchorPage: 1, naturalTargetOffset: pageExtent * 1.37 })).toBe(1);
  });

  it('clamps the deck boundaries and invalid geometry', () => {
    expect(target({ anchorPage: 0, naturalTargetOffset: -9999 })).toBe(0);
    expect(target({ anchorPage: 4, naturalTargetOffset: pageExtent * 99 })).toBe(4);
    expect(target({ pageExtent: 0 })).toBe(2);
    expect(target({ pageCount: 0 })).toBe(0);
  });

  it('rehydrates the native transport into caller-facing phase states', () => {
    expect(
      rehydratePagerState(
        nativeState({
          anchorPage: 2,
          phase: 'dragging',
        })
      ).phase
    ).toEqual({ anchorOffset: 0, anchorPage: 2, kind: 'dragging' });

    expect(
      rehydratePagerState(
        nativeState({
          anchorPage: 2,
          phase: 'settling',
          settlingSource: 'programmatic',
          targetPage: 4,
        })
      ).phase
    ).toEqual({ anchorPage: 2, kind: 'settling', source: 'programmatic', targetPage: 4 });

    expect(rehydratePagerState(nativeState({ page: 3 })).phase).toEqual({ kind: 'idle', page: 3 });
    expect(rehydratePagerState(nativeState({ pageCount: 0, phase: 'idle' })).phase).toEqual({ kind: 'empty' });
  });

  it('rejects an internally inconsistent settling transport', () => {
    expect(() => rehydratePagerState(nativeState({ phase: 'settling', settlingSource: 'none' }))).toThrow(
      'Pager entered the settling phase without a settling source.'
    );
  });
});
