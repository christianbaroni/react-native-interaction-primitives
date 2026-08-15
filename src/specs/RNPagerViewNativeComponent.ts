import type * as React from 'react';
import { codegenNativeComponent, type HostComponent, type ViewProps } from 'react-native';
import codegenNativeCommands from 'react-native/Libraries/Utilities/codegenNativeCommands';
import type { DirectEventHandler, Float, Int32, WithDefault } from 'react-native/Libraries/Types/CodegenTypes';

export type NativePagerState = Readonly<{
  anchorOffset: Float;
  anchorPage: Int32;
  offset: Float;
  page: Int32;
  pageCount: Int32;
  pageExtent: Float;
  phase: 'empty' | 'idle' | 'dragging' | 'settling';
  position: Float;
  settlingSource: 'none' | 'programmatic' | 'release';
  targetPage: Int32;
}>;

export type NativePagerPageChange = Readonly<{
  page: Int32;
}>;

export interface NativeProps extends ViewProps {
  initialPage?: Int32;
  onPageChange?: DirectEventHandler<NativePagerPageChange>;
  onPageScroll?: DirectEventHandler<NativePagerState>;
  onStateChange?: DirectEventHandler<NativePagerState>;
  orientation?: WithDefault<'horizontal' | 'vertical', 'horizontal'>;
  pageInset?: Float;
  pageChangeEventsEnabled?: WithDefault<boolean, false>;
  pageScrollEventsEnabled?: WithDefault<boolean, false>;
  pageSpacing?: Float;
  scrollEnabled?: WithDefault<boolean, true>;
  stateEventsEnabled?: WithDefault<boolean, false>;
}

interface NativeCommands {
  setPage(viewRef: React.ElementRef<HostComponent<NativeProps>>, page: Int32, animated: boolean): void;
}

export const Commands: NativeCommands = codegenNativeCommands<NativeCommands>({
  supportedCommands: ['setPage'],
});

export default codegenNativeComponent<NativeProps>('RNPagerView');
