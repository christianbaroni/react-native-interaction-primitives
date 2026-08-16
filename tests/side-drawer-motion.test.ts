import { describe, expect, it } from 'vitest';
import { compileSideDrawerMotion } from '../src/sideDrawerMotion';

describe('SideDrawer motion compilation', () => {
  it('compiles typed channels into one flat native config', () => {
    expect(
      compileSideDrawerMotion({
        drawer: { opacity: { inputRange: [0, 0.9], outputRange: [0.1, 1] } },
        overlay: { opacity: { inputRange: [0, 1], outputRange: [0, 0.42] } },
      })
    ).toEqual([2, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0.1, 0.9, 1, 0, 0, 1, 0.42]);
  });

  it('rejects interpolation configs that cannot be evaluated deterministically', () => {
    expect(() =>
      compileSideDrawerMotion({
        content: { opacity: { inputRange: [0, 0.5, 0.5], outputRange: [0, 0.5, 1] } },
      })
    ).toThrow('motion.content.opacity.inputRange must be finite, strictly increasing, and within [0, 1]');
    expect(() =>
      compileSideDrawerMotion({
        content: { scale: { inputRange: [0, 1], outputRange: [1] } },
      })
    ).toThrow('motion.content.scale must have matching input and output ranges of at least two points');
  });
});
