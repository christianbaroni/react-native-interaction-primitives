import type * as React from 'react';
import type { ViewProps } from 'react-native';

export type PagerPhase =
  | { kind: 'empty' }
  | { kind: 'idle'; page: number }
  | { kind: 'dragging'; anchorOffset: number; anchorPage: number }
  | { kind: 'settling'; anchorPage: number; source: 'programmatic' | 'release'; targetPage: number };

export type PagerState = Readonly<{
  offset: number;
  pageCount: number;
  pageExtent: number;
  phase: PagerPhase;
  position: number;
}>;

export type PagerPageChange = Readonly<{
  page: number;
}>;

export type PagerScrollPhase = 'empty' | 'idle' | 'dragging' | 'settling';

export type PagerScrollEvent = Readonly<{
  anchorOffset: number;
  anchorPage: number;
  offset: number;
  page: number;
  pageCount: number;
  pageExtent: number;
  phase: PagerScrollPhase;
  position: number;
  settlingSource: 'none' | 'programmatic' | 'release';
  targetPage: number;
}>;

export type PagerScrollNativeEvent = Readonly<{
  nativeEvent: PagerScrollEvent;
}>;

export type PagerProps = ViewProps & {
  children: React.ReactNode;
  initialPage?: number;
  onPageChange?: (event: PagerPageChange) => void;
  onPageScroll?: (event: PagerScrollNativeEvent) => void;
  onStateChange?: (state: PagerState) => void;
  orientation?: 'horizontal' | 'vertical';
  pageInset?: number;
  pageSpacing?: number;
  scrollEnabled?: boolean;
};

export type PagerSetPageOptions = Readonly<{
  animated?: boolean;
}>;

export type PagerRef = React.Component<PagerProps> & {
  setPage(page: number, options?: PagerSetPageOptions): void;
};

export type SideDrawerPhase = 'closed' | 'open' | 'dragging' | 'settling';

export type SideDrawerProgressEvent = Readonly<{
  phase: SideDrawerPhase;
  progress: number;
  settlingSource: 'none' | 'programmatic' | 'release';
  targetOpen: boolean;
}>;

export type SideDrawerProgressNativeEvent = Readonly<{
  nativeEvent: SideDrawerProgressEvent;
}>;

export type SideDrawerProps = ViewProps & {
  children: React.ReactElement;
  drawer: React.ReactElement;
  drawerWidth: number;
  edgeWidth?: number;
  gestureEnabled?: boolean;
  initialOpen?: boolean;
  onOpenChange?: (open: boolean) => void;
  onProgress?: (event: SideDrawerProgressNativeEvent) => void;
  side?: 'start' | 'end';
};

export type SideDrawerCommandOptions = Readonly<{
  animated?: boolean;
}>;

export type SideDrawerRef = React.Component<SideDrawerProps> & {
  close(options?: SideDrawerCommandOptions): void;
  open(options?: SideDrawerCommandOptions): void;
  toggle(options?: SideDrawerCommandOptions): void;
};
