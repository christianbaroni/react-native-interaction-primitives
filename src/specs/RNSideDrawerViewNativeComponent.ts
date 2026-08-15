import type * as React from 'react';
import { codegenNativeComponent, type HostComponent, type ViewProps } from 'react-native';
import codegenNativeCommands from 'react-native/Libraries/Utilities/codegenNativeCommands';
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
  drawerWidth: Float;
  edgeWidth?: Float;
  gestureEnabled?: WithDefault<boolean, true>;
  initialOpen?: WithDefault<boolean, false>;
  onOpenChange?: DirectEventHandler<NativeSideDrawerOpenChange>;
  onProgress?: DirectEventHandler<NativeSideDrawerProgress>;
  openChangeEventsEnabled?: WithDefault<boolean, false>;
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
