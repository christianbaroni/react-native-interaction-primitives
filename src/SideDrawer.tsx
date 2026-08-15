import * as React from 'react';
import { StyleSheet, View } from 'react-native';
import NativeSideDrawerContentView from './specs/RNSideDrawerContentViewNativeComponent';
import NativeSideDrawerPanelView from './specs/RNSideDrawerPanelViewNativeComponent';
import NativeSideDrawerView, { Commands, type NativeSideDrawerOpenChange } from './specs/RNSideDrawerViewNativeComponent';
import { compileSideDrawerMotion } from './sideDrawerMotion';
import type { SideDrawerCommandOptions, SideDrawerProps, SideDrawerRef } from './types';

type NativeSideDrawerRef = React.ComponentRef<typeof NativeSideDrawerView> | null;
type NativeSideDrawerEvent<T> = Readonly<{ nativeEvent: T }>;
type SideDrawerClass = React.ComponentClass<SideDrawerProps> & {
  new (props: SideDrawerProps, context?: unknown): SideDrawerRef;
};
type SideDrawerInternalProps = SideDrawerProps & {
  topProgress?: SideDrawerProps['onProgress'];
};

function requirePositiveFinite(value: number, name: string): void {
  if (!Number.isFinite(value) || value <= 0) {
    throw new RangeError(`${name} must be a finite number greater than zero.`);
  }
}

function requireNonNegativeFinite(value: number, name: string): void {
  if (!Number.isFinite(value) || value < 0) {
    throw new RangeError(`${name} must be a finite number greater than or equal to zero.`);
  }
}

class SideDrawerImplementation extends React.PureComponent<SideDrawerProps> implements SideDrawerRef {
  private compiledMotion: readonly number[] | undefined;
  private compiledMotionSource: SideDrawerProps['motion'];
  private nativeRef: NativeSideDrawerRef = null;

  getAnimatableRef() {
    return this.nativeRef;
  }

  close(options?: SideDrawerCommandOptions) {
    Commands.close(this.requireNativeRef(), options?.animated ?? true);
  }

  open(options?: SideDrawerCommandOptions) {
    Commands.open(this.requireNativeRef(), options?.animated ?? true);
  }

  toggle(options?: SideDrawerCommandOptions) {
    Commands.toggle(this.requireNativeRef(), options?.animated ?? true);
  }

  private requireNativeRef(): NonNullable<NativeSideDrawerRef> {
    if (this.nativeRef == null) throw new Error('SideDrawer is not mounted.');
    return this.nativeRef;
  }

  private setNativeRef = (ref: NativeSideDrawerRef) => {
    this.nativeRef = ref;
  };

  private handleOpenChange = (event: NativeSideDrawerEvent<NativeSideDrawerOpenChange>) => {
    this.props.onOpenChange?.(event.nativeEvent.open);
  };

  private motionConfigFor(motion: SideDrawerProps['motion']): readonly number[] {
    if (this.compiledMotion == null || this.compiledMotionSource !== motion) {
      this.compiledMotionSource = motion;
      this.compiledMotion = compileSideDrawerMotion(motion);
    }
    return this.compiledMotion;
  }

  render() {
    const internalProps: SideDrawerInternalProps = this.props;
    const {
      children,
      contentCornerRadius,
      drawer,
      drawerWidth,
      gestureEnabled = true,
      gestureReleaseHaptic = 'none',
      initialOpen = false,
      motion,
      onOpenChange,
      onProgress,
      side = 'start',
      topProgress,
      ...props
    } = internalProps;

    requirePositiveFinite(drawerWidth, 'drawerWidth');
    if (contentCornerRadius != null) requireNonNegativeFinite(contentCornerRadius, 'contentCornerRadius');
    const motionConfig = this.motionConfigFor(motion);

    // Reanimated Paper subscriptions use RN's normalized top* event name.
    void topProgress;

    return (
      <NativeSideDrawerView
        {...props}
        contentCornerRadius={contentCornerRadius ?? -1}
        drawerWidth={drawerWidth}
        gestureEnabled={gestureEnabled}
        gestureReleaseHaptic={gestureReleaseHaptic}
        initialOpen={initialOpen}
        motionConfig={motionConfig}
        onOpenChange={onOpenChange ? this.handleOpenChange : undefined}
        onProgress={onProgress}
        openChangeEventsEnabled={onOpenChange != null}
        overlayColor={motion?.overlay?.color ?? 'transparent'}
        progressEventsEnabled={onProgress != null || topProgress != null}
        ref={this.setNativeRef}
        side={side}
      >
        <NativeSideDrawerPanelView collapsable={false} style={styles.panel}>
          <View
            collapsable={false}
            style={[styles.drawerContent, side === 'start' ? styles.drawerContentStart : styles.drawerContentEnd, { width: drawerWidth }]}
          >
            {drawer}
          </View>
        </NativeSideDrawerPanelView>
        <NativeSideDrawerContentView collapsable={false} style={styles.content}>
          {children}
        </NativeSideDrawerContentView>
      </NativeSideDrawerView>
    );
  }
}

const styles = StyleSheet.create({
  content: StyleSheet.absoluteFill,
  drawerContent: {
    bottom: 0,
    position: 'absolute',
    top: 0,
  },
  drawerContentEnd: {
    end: 0,
  },
  drawerContentStart: {
    start: 0,
  },
  panel: StyleSheet.absoluteFill,
});

export const SideDrawer: SideDrawerClass = SideDrawerImplementation;
