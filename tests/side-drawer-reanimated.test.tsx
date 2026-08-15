import { act, renderHook } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { useSideDrawer } from '../src/reanimated';
import type { SideDrawerProgressEvent } from '../src/types';

const progressEvent: SideDrawerProgressEvent = {
  phase: 'settling',
  progress: 0.64,
  settlingSource: 'release',
  targetOpen: true,
};

describe('SideDrawer Reanimated observation', () => {
  it('projects native progress without becoming an animation owner', () => {
    const { result } = renderHook(useSideDrawer);

    act(() => result.current.onProgress({ nativeEvent: progressEvent }));

    expect(result.current.progress.value).toBe(0.64);
    expect(result.current.phase.value).toBe('settling');
    expect(result.current.settlingSource.value).toBe('release');
    expect(result.current.targetOpen.value).toBe(true);
  });
});
