import { act, render } from '@testing-library/react';
import * as React from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { Pager } from '../src/Pager';
import * as Package from '../src';
import type { PagerRef } from '../src/types';
import { __clearNativeCommandCalls, __getNativeCommandCalls } from './mocks/codegenNativeCommands';
import { __clearNativeComponentRenderLog, __getNativeComponentRenderLog } from './mocks/codegenNativeComponent';

type NativeEvent<T> = Readonly<{ nativeEvent: T }>;

function callNativeEvent<T>(handler: unknown, nativeEvent: T): void {
  if (typeof handler !== 'function') throw new Error('Native event handler is not attached.');
  Reflect.apply(handler, undefined, [{ nativeEvent } satisfies NativeEvent<T>]);
}

function nativeProps(name: string): Record<string, unknown>[] {
  return __getNativeComponentRenderLog().filter(props => props['data-native-component'] === name);
}

function lastNativeProps(name: string): Record<string, unknown> {
  const props = nativeProps(name).at(-1);
  if (props == null) throw new Error(`No ${name} render was recorded.`);
  return props;
}

beforeEach(() => {
  __clearNativeCommandCalls();
  __clearNativeComponentRenderLog();
});

describe('Pager API', () => {
  it('exports the standalone pager without exporting its native page host', () => {
    expect(Package.Pager).toBe(Pager);
    expect('PagerPage' in Package).toBe(false);

    const ref = React.createRef<PagerRef>();
    render(
      <Pager ref={ref}>
        <span>page</span>
      </Pager>
    );

    expect(typeof ref.current?.setPage).toBe('function');
  });

  it('normalizes non-null children through private native page hosts', () => {
    render(
      <Pager>
        <span key="first">first</span>
        {null}
        {false}
        <span key="second">second</span>
      </Pager>
    );

    expect(nativeProps('RNPagerView')).toHaveLength(1);
    expect(nativeProps('RNPagerPageView')).toHaveLength(2);
  });

  it('enables continuous native events only when a scroll observer is attached', () => {
    const { rerender } = render(
      <Pager>
        <span>page</span>
      </Pager>
    );
    expect(lastNativeProps('RNPagerView').pageChangeEventsEnabled).toBe(false);
    expect(lastNativeProps('RNPagerView').pageScrollEventsEnabled).toBe(false);
    expect(lastNativeProps('RNPagerView').stateEventsEnabled).toBe(false);

    const onPageScroll = vi.fn();
    rerender(
      <Pager onPageScroll={onPageScroll}>
        <span>page</span>
      </Pager>
    );
    expect(lastNativeProps('RNPagerView').pageScrollEventsEnabled).toBe(true);
    expect(lastNativeProps('RNPagerView').onPageScroll).toBe(onPageScroll);

    const onStateChange = vi.fn();
    rerender(
      <Pager onStateChange={onStateChange}>
        <span>page</span>
      </Pager>
    );
    expect(lastNativeProps('RNPagerView').pageScrollEventsEnabled).toBe(false);
    expect(lastNativeProps('RNPagerView').stateEventsEnabled).toBe(true);

    const onPageChange = vi.fn();
    rerender(
      <Pager onPageChange={onPageChange}>
        <span>page</span>
      </Pager>
    );
    expect(lastNativeProps('RNPagerView').pageChangeEventsEnabled).toBe(true);
  });

  it('requests the attachment snapshot after enclosing mount lifecycles', async () => {
    class AnimatedParent extends React.Component<React.PropsWithChildren> {
      componentDidMount() {
        expect(__getNativeCommandCalls()).toHaveLength(0);
      }

      render() {
        return this.props.children;
      }
    }

    render(
      <AnimatedParent>
        <Pager onPageScroll={vi.fn()}>
          <span>page</span>
        </Pager>
      </AnimatedParent>
    );
    await act(async () => {});
    expect(__getNativeCommandCalls().map(call => call.name)).toEqual(['requestPageScrollSnapshot']);
  });

  it('requests a snapshot on attachment and skips unchanged observation', async () => {
    const onPageScroll = vi.fn();
    const { rerender } = render(<Pager>{null}</Pager>);
    await act(async () => {});
    expect(__getNativeCommandCalls()).toHaveLength(0);

    rerender(<Pager onPageScroll={onPageScroll}>{null}</Pager>);
    await act(async () => {});
    expect(__getNativeCommandCalls().map(call => call.name)).toEqual(['requestPageScrollSnapshot']);

    rerender(
      <Pager initialPage={1} onPageScroll={onPageScroll}>
        {null}
      </Pager>
    );
    await act(async () => {});
    expect(__getNativeCommandCalls()).toHaveLength(1);
  });

  it('drops queued snapshot requests when observation ends or the pager unmounts', async () => {
    const { rerender, unmount } = render(<Pager onPageScroll={vi.fn()}>{null}</Pager>);
    rerender(<Pager>{null}</Pager>);
    await act(async () => {});
    expect(__getNativeCommandCalls()).toHaveLength(0);

    rerender(<Pager onPageScroll={vi.fn()}>{null}</Pager>);
    unmount();
    await act(async () => {});
    expect(__getNativeCommandCalls()).toHaveLength(0);
  });

  it('rehydrates state events and narrows page-change events at the public boundary', () => {
    const onPageChange = vi.fn();
    const onStateChange = vi.fn();
    render(
      <Pager onPageChange={onPageChange} onStateChange={onStateChange}>
        <span>page</span>
      </Pager>
    );

    const props = lastNativeProps('RNPagerView');
    act(() => {
      callNativeEvent(props.onPageChange, { page: 0 });
      callNativeEvent(props.onStateChange, {
        anchorOffset: 0,
        anchorPage: 0,
        offset: 0,
        page: 0,
        pageCount: 1,
        pageExtent: 320,
        phase: 'idle',
        position: 0,
        settlingSource: 'none',
        targetPage: -1,
      });
    });

    expect(onPageChange).toHaveBeenCalledWith({ page: 0 });
    expect(onStateChange).toHaveBeenCalledWith({
      offset: 0,
      pageCount: 1,
      pageExtent: 320,
      phase: { kind: 'idle', page: 0 },
      position: 0,
    });
  });

  it('rejects invalid imperative targets before crossing the native boundary', () => {
    const ref = React.createRef<PagerRef>();
    render(
      <Pager ref={ref}>
        <span>page</span>
      </Pager>
    );

    expect(() => ref.current?.setPage(-1)).toThrow('Pager page -1 is outside the mounted range 0..0.');
    expect(() => ref.current?.setPage(1)).toThrow('Pager page 1 is outside the mounted range 0..0.');
    expect(() => ref.current?.setPage(0.5)).toThrow('Pager page 0.5 is outside the mounted range 0..0.');
    expect(__getNativeCommandCalls()).toHaveLength(0);

    ref.current?.setPage(0, { animated: false });
    expect(__getNativeCommandCalls()).toEqual([
      {
        args: [expect.objectContaining({ name: 'RNPagerView' }), 0, false],
        name: 'setPage',
      },
    ]);
  });
});
