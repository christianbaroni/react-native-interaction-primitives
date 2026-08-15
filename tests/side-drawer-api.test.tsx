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
  });

  it('defaults content clipping to the native screen radius', () => {
    const { rerender } = render(drawer());
    expect(lastNativeProps('RNSideDrawerView').contentCornerRadius).toBe(-1);

    rerender(drawer(undefined, { contentCornerRadius: 0 }));
    expect(lastNativeProps('RNSideDrawerView').contentCornerRadius).toBe(0);
  });

  it('enables release haptics only when a feedback type is present', () => {
    const { rerender } = render(drawer());
    expect(lastNativeProps('RNSideDrawerView').gestureReleaseHaptic).toBe('none');

    rerender(drawer(undefined, { gestureReleaseHaptic: 'soft' }));
    expect(lastNativeProps('RNSideDrawerView').gestureReleaseHaptic).toBe('soft');
  });

  it('compiles declarative motion into one native configuration', () => {
    const motion = {
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
      motionConfig: [2, 2, 0, 0, 0, 0, 0, 0, 2, 0, 0.1, 0.9, 1, 0, 0.94, 1, 1, 0, 0, 1, 0.4],
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
