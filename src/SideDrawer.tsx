import * as React from 'react';
import { StyleSheet } from 'react-native';
import NativeSideDrawerContentView from './specs/RNSideDrawerContentViewNativeComponent';
import NativeSideDrawerPanelView from './specs/RNSideDrawerPanelViewNativeComponent';
import NativeSideDrawerView, { Commands, type NativeSideDrawerOpenChange } from './specs/RNSideDrawerViewNativeComponent';
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

function requireNonnegativeFinite(value: number, name: string): void {
  if (!Number.isFinite(value) || value < 0) {
    throw new RangeError(`${name} must be a finite nonnegative number.`);
  }
}

class SideDrawerImplementation extends React.PureComponent<SideDrawerProps> implements SideDrawerRef {
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

  render() {
    const internalProps: SideDrawerInternalProps = this.props;
    const {
      children,
      drawer,
      drawerWidth,
      edgeWidth = 24,
      gestureEnabled = true,
      initialOpen = false,
      onOpenChange,
      onProgress,
      side = 'start',
      topProgress,
      ...props
    } = internalProps;

    requirePositiveFinite(drawerWidth, 'drawerWidth');
    requireNonnegativeFinite(edgeWidth, 'edgeWidth');

    // Reanimated Paper subscriptions use RN's normalized top* event name.
    void topProgress;

    return (
      <NativeSideDrawerView
        {...props}
        drawerWidth={drawerWidth}
        edgeWidth={edgeWidth}
        gestureEnabled={gestureEnabled}
        initialOpen={initialOpen}
        onOpenChange={onOpenChange ? this.handleOpenChange : undefined}
        onProgress={onProgress}
        openChangeEventsEnabled={onOpenChange != null}
        progressEventsEnabled={onProgress != null || topProgress != null}
        ref={this.setNativeRef}
        side={side}
      >
        <NativeSideDrawerPanelView
          collapsable={false}
          style={[styles.panel, side === 'start' ? styles.panelStart : styles.panelEnd, { width: drawerWidth }]}
        >
          {drawer}
        </NativeSideDrawerPanelView>
        <NativeSideDrawerContentView collapsable={false} style={styles.content}>
          {children}
        </NativeSideDrawerContentView>
      </NativeSideDrawerView>
    );
  }
}

const styles = StyleSheet.create({
  content: StyleSheet.absoluteFillObject,
  panel: {
    bottom: 0,
    position: 'absolute',
    top: 0,
  },
  panelEnd: {
    end: 0,
  },
  panelStart: {
    start: 0,
  },
});

export const SideDrawer: SideDrawerClass = SideDrawerImplementation;
