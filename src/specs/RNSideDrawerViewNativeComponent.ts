import type * as React from 'react';
import { codegenNativeCommands, codegenNativeComponent, type ColorValue, type HostComponent, type ViewProps } from 'react-native';
import type { DirectEventHandler, Float, WithDefault } from 'react-native/Libraries/Types/CodegenTypes';

export type NativeSideDrawerOpenChange = Readonly<{
  open: boolean;
}>;

export type NativeSideDrawerProgress = Readonly<{
  phase: 'closed' | 'open' | 'dragging' | 'settling';
  progress: Float;
  settlingSource: 'none' | 'programmatic' | 'release';
  targetOpen: boolean;
}>;

export interface NativeProps extends ViewProps {
  contentBorderColor?: ColorValue;
  contentBorderWidth?: WithDefault<Float, 0>;
  contentCornerRadius?: WithDefault<Float, -1>;
  drawerWidth: Float;
  gestureEnabled?: WithDefault<boolean, true>;
  gestureReleaseHaptic?: WithDefault<
    'none' | 'selection' | 'light' | 'medium' | 'heavy' | 'soft' | 'rigid' | 'success' | 'warning' | 'error',
    'none'
  >;
  initialOpen?: WithDefault<boolean, false>;
  motionConfig?: ReadonlyArray<Float>;
  onOpenChange?: DirectEventHandler<NativeSideDrawerOpenChange>;
  onProgress?: DirectEventHandler<NativeSideDrawerProgress>;
  openChangeEventsEnabled?: WithDefault<boolean, false>;
  overlayColor?: ColorValue;
  progressEventsEnabled?: WithDefault<boolean, false>;
  side?: WithDefault<'start' | 'end', 'start'>;
}

interface NativeCommands {
  close(viewRef: React.ElementRef<HostComponent<NativeProps>>, animated: boolean): void;
  open(viewRef: React.ElementRef<HostComponent<NativeProps>>, animated: boolean): void;
  toggle(viewRef: React.ElementRef<HostComponent<NativeProps>>, animated: boolean): void;
}

export const Commands: NativeCommands = codegenNativeCommands<NativeCommands>({
  supportedCommands: ['close', 'open', 'toggle'],
});

export default codegenNativeComponent<NativeProps>('RNSideDrawerView');
