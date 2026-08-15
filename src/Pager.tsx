import * as React from 'react';
import { rehydratePagerState } from './pagerModel';
import NativePagerPageView from './specs/RNPagerPageViewNativeComponent';
import NativePagerView, { Commands, type NativePagerPageChange, type NativePagerState } from './specs/RNPagerViewNativeComponent';
import type { PagerPageChange, PagerProps, PagerRef, PagerSetPageOptions, PagerState } from './types';

type NativePagerRef = React.ComponentRef<typeof NativePagerView> | null;
type NativePagerEvent<T> = Readonly<{ nativeEvent: T }>;
type PagerClass = React.ComponentClass<PagerProps> & {
  new (props: PagerProps, context?: unknown): PagerRef;
};
type PagerInternalProps = PagerProps & {
  topPageScroll?: PagerProps['onPageScroll'];
};

function pagerPagesFromChildren(children: React.ReactNode): React.ReactNode[] {
  const pages: React.ReactNode[] = [];
  React.Children.forEach(children, child => {
    if (child == null) return;
    const key = React.isValidElement(child) && child.key != null ? child.key : pages.length;
    pages.push(
      <NativePagerPageView collapsable={false} key={key}>
        {child}
      </NativePagerPageView>
    );
  });
  return pages;
}

function pagerPageCountFromChildren(children: React.ReactNode): number {
  let pageCount = 0;
  React.Children.forEach(children, child => {
    if (child != null) pageCount += 1;
  });
  return pageCount;
}

function assertPage(page: number, pageCount: number): void {
  if (!Number.isInteger(page) || page < 0 || page >= pageCount) {
    throw new RangeError(`Pager page ${page} is outside the mounted range 0..${Math.max(0, pageCount - 1)}.`);
  }
}

class PagerImplementation extends React.PureComponent<PagerProps> implements PagerRef {
  private nativeRef: NativePagerRef = null;
  private pageCount = 0;

  componentDidMount() {
    this.pageCount = pagerPageCountFromChildren(this.props.children);
  }

  componentDidUpdate(previousProps: PagerProps) {
    if (previousProps.children !== this.props.children) {
      this.pageCount = pagerPageCountFromChildren(this.props.children);
    }
  }

  getAnimatableRef() {
    return this.nativeRef;
  }

  setPage(page: number, options?: PagerSetPageOptions) {
    assertPage(page, this.pageCount);
    if (this.nativeRef == null) {
      throw new Error('Pager is not mounted.');
    }
    Commands.setPage(this.nativeRef, page, options?.animated ?? true);
  }

  private setNativeRef = (ref: NativePagerRef) => {
    this.nativeRef = ref;
  };

  private handlePageChange = (event: NativePagerEvent<NativePagerPageChange>) => {
    const change: PagerPageChange = { page: event.nativeEvent.page };
    this.props.onPageChange?.(change);
  };

  private handleStateChange = (event: NativePagerEvent<NativePagerState>) => {
    const state: PagerState = rehydratePagerState(event.nativeEvent);
    this.props.onStateChange?.(state);
  };

  render() {
    const internalProps: PagerInternalProps = this.props;
    const { children, onPageChange, onPageScroll, onStateChange, scrollEnabled = true, topPageScroll, ...props } = internalProps;
    const pages = pagerPagesFromChildren(children);

    // Reanimated Paper subscriptions use RN's normalized top* event name.
    void topPageScroll;

    return (
      <NativePagerView
        {...props}
        onPageChange={onPageChange ? this.handlePageChange : undefined}
        onPageScroll={onPageScroll}
        onStateChange={onStateChange ? this.handleStateChange : undefined}
        pageChangeEventsEnabled={onPageChange != null}
        pageScrollEventsEnabled={onPageScroll != null || topPageScroll != null}
        ref={this.setNativeRef}
        scrollEnabled={scrollEnabled}
        stateEventsEnabled={onStateChange != null}
      >
        {pages}
      </NativePagerView>
    );
  }
}

export const Pager: PagerClass = PagerImplementation;
