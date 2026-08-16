import { render } from '@testing-library/react';
import * as React from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { SideDrawer } from '../src/SideDrawer';
import * as Package from '../src';
import type { SideDrawerRef } from '../src/types';
import { __clearNativeCommandCalls, __getNativeCommandCalls } from './mocks/codegenNativeCommands';
import { __clearNativeComponentRenderLog, __getNativeComponentRenderLog } from './mocks/codegenNativeComponent';

function nativeProps(name: string): Record<string, unknown>[] {
  return __getNativeComponentRenderLog().filter(props => props['data-native-component'] === name);
}

function lastNativeProps(name: string): Record<string, unknown> {
  const props = nativeProps(name).at(-1);
  if (props == null) throw new Error(`No ${name} render was recorded.`);
  return props;
}

function callNativeEvent<T>(handler: unknown, nativeEvent: T): void {
  if (typeof handler !== 'function') throw new Error('Native event handler is not attached.');
  Reflect.apply(handler, undefined, [{ nativeEvent }]);
}

function drawer(ref?: React.Ref<SideDrawerRef>, props: Partial<React.ComponentProps<typeof SideDrawer>> = {}) {
  return (
    <SideDrawer drawer={<span>drawer</span>} drawerWidth={280} ref={ref} {...props}>
      <span>content</span>
    </SideDrawer>
  );
}

beforeEach(() => {
  __clearNativeCommandCalls();
  __clearNativeComponentRenderLog();
});

describe('SideDrawer API', () => {
  it('exports one public drawer backed by two private native roles', () => {
    expect(Package.SideDrawer).toBe(SideDrawer);
    expect('SideDrawerPanel' in Package).toBe(false);
    render(drawer());

    expect(nativeProps('RNSideDrawerView')).toHaveLength(1);
    expect(nativeProps('RNSideDrawerPanelView')).toHaveLength(1);
    expect(nativeProps('RNSideDrawerContentView')).toHaveLength(1);
  });

  it('derives native event gates from attached observers', () => {
    const { rerender } = render(drawer());
    expect(lastNativeProps('RNSideDrawerView').openChangeEventsEnabled).toBe(false);
    expect(lastNativeProps('RNSideDrawerView').progressEventsEnabled).toBe(false);

    rerender(drawer(undefined, { onOpenChange: vi.fn(), onProgress: vi.fn() }));
    expect(lastNativeProps('RNSideDrawerView').openChangeEventsEnabled).toBe(true);
    expect(lastNativeProps('RNSideDrawerView').progressEventsEnabled).toBe(true);
  });

  it('narrows the native open-change event to the settled boolean', () => {
    const onOpenChange = vi.fn();
    render(drawer(undefined, { onOpenChange }));

    callNativeEvent(lastNativeProps('RNSideDrawerView').onOpenChange, { open: true });

    expect(onOpenChange).toHaveBeenCalledWith(true);
  });

  it('validates product geometry before crossing the native boundary', () => {
    expect(() => render(drawer(undefined, { drawerWidth: 0 }))).toThrow('drawerWidth must be a finite number greater than zero.');
    expect(() => render(drawer(undefined, { contentCornerRadius: -1 }))).toThrow(
      'contentCornerRadius must be a finite number greater than or equal to zero.'
    );
    expect(() =>
      render(
        drawer(undefined, {
          motion: { content: { border: { color: 'black', width: -1 } } },
        })
      )
    ).toThrow('motion.content.border.width must be a finite number greater than or equal to zero.');
    expect(() =>
      render(
        drawer(undefined, {
          motion: { content: { shadow: { android: { elevation: -1 }, color: 'black' } } },
        })
      )
    ).toThrow('motion.content.shadow.android.elevation must be a finite number greater than or equal to zero.');
    expect(() =>
      render(
        drawer(undefined, {
          motion: { content: { shadow: { color: 'black', ios: { radius: -1 } } } },
        })
      )
    ).toThrow('motion.content.shadow.ios.radius must be a finite number greater than or equal to zero.');
  });

  it('defaults content clipping to the native screen radius', () => {
    const { rerender } = render(drawer());
    expect(lastNativeProps('RNSideDrawerView').contentCornerRadius).toBe(-1);

    rerender(drawer(undefined, { contentCornerRadius: 0 }));
    expect(lastNativeProps('RNSideDrawerView').contentCornerRadius).toBe(0);
  });

  it('omits the border by default and uses one layout unit when present', () => {
    const { rerender } = render(drawer());
    expect(lastNativeProps('RNSideDrawerView')).toMatchObject({
      contentBorderColor: 'transparent',
      contentBorderWidth: 0,
    });

    rerender(drawer(undefined, { motion: { content: { border: { color: 'white' } } } }));
    expect(lastNativeProps('RNSideDrawerView')).toMatchObject({
      contentBorderColor: 'white',
      contentBorderWidth: 1,
    });
  });

  it('omits the shadow by default and applies native geometry defaults when present', () => {
    const { rerender } = render(drawer());
    expect(lastNativeProps('RNSideDrawerView')).toMatchObject({
      contentShadowColor: 'transparent',
      contentShadowElevation: 0,
      contentShadowOffsetX: 0,
      contentShadowOffsetY: 0,
      contentShadowRadius: 0,
    });

    rerender(
      drawer(undefined, {
        motion: {
          content: {
            shadow: {
              color: '#00000088',
            },
          },
        },
      })
    );
    expect(lastNativeProps('RNSideDrawerView')).toMatchObject({
      contentShadowColor: '#00000088',
      contentShadowElevation: 16,
      contentShadowOffsetX: 0,
      contentShadowOffsetY: 0,
      contentShadowRadius: 16,
    });

    rerender(
      drawer(undefined, {
        motion: {
          content: {
            shadow: {
              android: { elevation: 0 },
              color: '#00000088',
              ios: { offset: { x: -3, y: 1 }, radius: 0 },
            },
          },
        },
      })
    );
    expect(lastNativeProps('RNSideDrawerView')).toMatchObject({
      contentShadowElevation: 0,
      contentShadowOffsetX: -3,
      contentShadowOffsetY: 1,
      contentShadowRadius: 0,
    });
  });

  it('enables release haptics only when a feedback type is present', () => {
    const { rerender } = render(drawer());
    expect(lastNativeProps('RNSideDrawerView').gestureReleaseHaptic).toBe('none');

    rerender(drawer(undefined, { gestureReleaseHaptic: 'soft' }));
    expect(lastNativeProps('RNSideDrawerView').gestureReleaseHaptic).toBe('soft');
  });

  it('maps interaction defaults and physical tuning to native scalars', () => {
    const { rerender } = render(drawer());
    expect(lastNativeProps('RNSideDrawerView')).toMatchObject({
      overdrag: 4,
      releaseOpenThreshold: 0.5,
      releaseVelocitySensitivity: 1,
      releaseVelocityTransfer: 1,
      springMass: 1,
    });
    expect(lastNativeProps('RNSideDrawerView').springDamping).toBeCloseTo(14 * Math.PI);
    expect(lastNativeProps('RNSideDrawerView').springStiffness).toBeCloseTo((7 * Math.PI) ** 2);

    rerender(
      drawer(undefined, {
        interaction: {
          overdrag: 2,
          release: {
            openThreshold: 0.4,
            velocitySensitivity: 1.25,
            velocityTransfer: 0.75,
          },
          spring: {
            damping: 24,
            mass: 1.4,
            stiffness: 520,
          },
        },
      })
    );
    expect(lastNativeProps('RNSideDrawerView')).toMatchObject({
      overdrag: 2,
      releaseOpenThreshold: 0.4,
      releaseVelocitySensitivity: 1.25,
      releaseVelocityTransfer: 0.75,
      springDamping: 24,
      springMass: 1.4,
      springStiffness: 520,
    });
  });

  it('rejects interaction values that cannot describe a completing native transition', () => {
    expect(() =>
      render(
        drawer(undefined, {
          interaction: { spring: { damping: 1e308, mass: 1e308, stiffness: 1e308 } },
        })
      )
    ).not.toThrow();
    expect(() => render(drawer(undefined, { interaction: { spring: { mass: 0 } } }))).toThrow(
      'interaction.spring.mass must be a finite number greater than zero.'
    );
    expect(() => render(drawer(undefined, { interaction: { spring: { stiffness: Number.POSITIVE_INFINITY } } }))).toThrow(
      'interaction.spring.stiffness must be a finite number greater than zero.'
    );
    expect(() => render(drawer(undefined, { interaction: { spring: { damping: 0 } } }))).toThrow(
      'interaction.spring.damping must be a finite number greater than zero.'
    );
    expect(() =>
      render(
        drawer(undefined, {
          interaction: { spring: { mass: Number.MIN_VALUE, stiffness: Number.MAX_VALUE } },
        })
      )
    ).toThrow('interaction.spring must produce finite positive frequency and damping.');
    expect(() => render(drawer(undefined, { interaction: { release: { openThreshold: 1.1 } } }))).toThrow(
      'interaction.release.openThreshold must be a finite number between zero and one.'
    );
    expect(() => render(drawer(undefined, { interaction: { release: { velocitySensitivity: -1 } } }))).toThrow(
      'interaction.release.velocitySensitivity must be a finite number greater than or equal to zero.'
    );
    expect(() => render(drawer(undefined, { interaction: { release: { velocityTransfer: -1 } } }))).toThrow(
      'interaction.release.velocityTransfer must be a finite number greater than or equal to zero.'
    );
    expect(() => render(drawer(undefined, { interaction: { overdrag: -1 } }))).toThrow(
      'interaction.overdrag must be a finite number greater than or equal to zero.'
    );
  });

  it('compiles declarative motion into one native configuration', () => {
    const motion = {
      content: {
        border: {
          color: '#AABBCC',
          opacity: { inputRange: [0, 0.8, 1], outputRange: [0, 0.6, 1] },
          width: 2,
        },
        shadow: {
          android: { elevation: 18 },
          color: '#00000088',
          ios: { offset: { x: -3, y: 1 }, radius: 20 },
          opacity: { inputRange: [0, 1], outputRange: [0, 0.8] },
        },
      },
      drawer: {
        opacity: { inputRange: [0, 0.9], outputRange: [0.1, 1] },
        scale: { inputRange: [0, 1], outputRange: [0.94, 1] },
      },
      overlay: {
        color: '#112233',
        opacity: { inputRange: [0, 1], outputRange: [0, 0.4] },
      },
    } as const;
    const { rerender } = render(drawer(undefined, { motion }));
    const firstMotionConfig = lastNativeProps('RNSideDrawerView').motionConfig;

    expect(lastNativeProps('RNSideDrawerView')).toMatchObject({
      contentBorderColor: '#AABBCC',
      contentBorderWidth: 2,
      contentShadowColor: '#00000088',
      contentShadowElevation: 18,
      contentShadowOffsetX: -3,
      contentShadowOffsetY: 1,
      contentShadowRadius: 20,
      motionConfig: [2, 2, 0, 0, 0, 0, 0, 0, 2, 3, 2, 0, 0.1, 0.9, 1, 0, 0.94, 1, 1, 0, 0, 1, 0.4, 0, 0, 0.8, 0.6, 1, 1, 0, 0, 1, 0.8],
      overlayColor: '#112233',
    });

    rerender(
      drawer(undefined, {
        motion,
        style: {
          flex: 1,
        },
      })
    );
    expect(lastNativeProps('RNSideDrawerView').motionConfig).toBe(firstMotionConfig);
  });

  it('dispatches native open, close, and toggle commands through its ref', () => {
    const ref = React.createRef<SideDrawerRef>();
    render(drawer(ref));

    ref.current?.open();
    ref.current?.close({ animated: false });
    ref.current?.toggle();

    expect(__getNativeCommandCalls()).toEqual([
      { args: [expect.objectContaining({ name: 'RNSideDrawerView' }), true], name: 'open' },
      { args: [expect.objectContaining({ name: 'RNSideDrawerView' }), false], name: 'close' },
      { args: [expect.objectContaining({ name: 'RNSideDrawerView' }), true], name: 'toggle' },
    ]);
  });
});
