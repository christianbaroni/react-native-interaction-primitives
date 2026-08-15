import { act, renderHook } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { usePager } from '../src/reanimated';
import type { PagerScrollEvent } from '../src/types';

const scrollEvent: PagerScrollEvent = {
  anchorOffset: 320,
  anchorPage: 1,
  offset: 416,
  page: 1,
  pageCount: 4,
  pageExtent: 320,
  phase: 'dragging',
  position: 1.3,
  settlingSource: 'none',
  targetPage: -1,
};

describe('Pager Reanimated observation', () => {
  it('projects the direct native event into shared values without owning motion', () => {
    const { result } = renderHook(usePager);

    act(() => result.current.onPageScroll({ nativeEvent: scrollEvent }));

    expect(result.current.offset.value).toBe(416);
    expect(result.current.page.value).toBe(1);
    expect(result.current.phase.value).toBe('dragging');
    expect(result.current.position.value).toBe(1.3);
  });
});
