import type * as React from 'react';
import { codegenNativeCommands, codegenNativeComponent, type ColorValue, type HostComponent, type ViewProps } from 'react-native';
import type { DirectEventHandler, Double, Float, WithDefault } from 'react-native/Libraries/Types/CodegenTypes';

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
  contentShadowColor?: ColorValue;
  contentShadowElevation?: WithDefault<Float, 0>;
  contentShadowOffsetX?: WithDefault<Float, 0>;
  contentShadowOffsetY?: WithDefault<Float, 0>;
  contentShadowRadius?: WithDefault<Float, 0>;
  drawerWidth: Float;
  gestureEnabled?: WithDefault<boolean, true>;
  gestureReleaseHaptic?: WithDefault<
    'none' | 'selection' | 'light' | 'medium' | 'heavy' | 'soft' | 'rigid' | 'success' | 'warning' | 'error',
    'none'
  >;
  initialOpen?: WithDefault<boolean, false>;
  motionConfig?: ReadonlyArray<Float>;
  overdrag?: WithDefault<Double, 4>;
  onOpenChange?: DirectEventHandler<NativeSideDrawerOpenChange>;
  onProgress?: DirectEventHandler<NativeSideDrawerProgress>;
  openChangeEventsEnabled?: WithDefault<boolean, false>;
  overlayColor?: ColorValue;
  progressEventsEnabled?: WithDefault<boolean, false>;
  releaseOpenThreshold?: WithDefault<Double, 0.5>;
  releaseVelocitySensitivity?: WithDefault<Double, 1>;
  releaseVelocityTransfer?: WithDefault<Double, 1>;
  side?: WithDefault<'start' | 'end', 'start'>;
  springDamping?: WithDefault<Double, 46>;
  springMass?: WithDefault<Double, 0.8>;
  springStiffness?: WithDefault<Double, 680>;
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
