import * as React from 'react';
import { StyleSheet, View } from 'react-native';
import NativeSideDrawerContentView from './specs/RNSideDrawerContentViewNativeComponent';
import NativeSideDrawerPanelView from './specs/RNSideDrawerPanelViewNativeComponent';
import NativeSideDrawerView, {
  Commands,
  type NativeSideDrawerTransitionEnd,
  type NativeSideDrawerTransitionStart,
} from './specs/RNSideDrawerViewNativeComponent';
import { compileSideDrawerMotion } from './sideDrawerMotion';
import type { SideDrawerCommandOptions, SideDrawerProps, SideDrawerRef } from './types';

const DEFAULT_ANDROID_SHADOW_ELEVATION = 16;
const DEFAULT_IOS_SHADOW_RADIUS = 16;
const DEFAULT_OVERDRAG = 4;
const DEFAULT_RELEASE_OPEN_THRESHOLD = 0.5;
const DEFAULT_RELEASE_VELOCITY_SENSITIVITY = 1;
const DEFAULT_RELEASE_VELOCITY_TRANSFER = 1;
const DEFAULT_SPRING_DAMPING = 46;
const DEFAULT_SPRING_MASS = 0.8;
const DEFAULT_SPRING_STIFFNESS = 680;

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

function requireUnitInterval(value: number, name: string): void {
  if (!Number.isFinite(value) || value < 0 || value > 1) {
    throw new RangeError(`${name} must be a finite number between zero and one.`);
  }
}

function requireFiniteSpringDynamics(mass: number, stiffness: number, damping: number): void {
  const frequencySquared = stiffness / mass;
  const dampingRate = damping / 2 / mass;
  if (!Number.isFinite(frequencySquared) || frequencySquared <= 0 || !Number.isFinite(dampingRate) || dampingRate <= 0) {
    throw new RangeError('interaction.spring must produce finite positive frequency and damping.');
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

  private handleTransitionEnd = (event: NativeSideDrawerEvent<NativeSideDrawerTransitionEnd>) => {
    const { open, changed } = event.nativeEvent;
    if (changed) this.props.onOpenChange?.(open);
    this.props.onTransitionEnd?.(open);
  };

  private handleTransitionStart = (event: NativeSideDrawerEvent<NativeSideDrawerTransitionStart>) => {
    this.props.onTransitionStart?.(event.nativeEvent.open);
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
      interaction,
      motion,
      onOpenChange,
      onProgress,
      onTransitionEnd,
      onTransitionStart,
      side = 'start',
      topProgress,
      ...props
    } = internalProps;

    requirePositiveFinite(drawerWidth, 'drawerWidth');
    if (contentCornerRadius != null) requireNonNegativeFinite(contentCornerRadius, 'contentCornerRadius');
    const contentBorder = motion?.content?.border;
    if (contentBorder?.width != null) requireNonNegativeFinite(contentBorder.width, 'motion.content.border.width');
    const contentShadow = motion?.content?.shadow;
    if (contentShadow?.android?.elevation != null) {
      requireNonNegativeFinite(contentShadow.android.elevation, 'motion.content.shadow.android.elevation');
    }
    if (contentShadow?.ios?.radius != null) {
      requireNonNegativeFinite(contentShadow.ios.radius, 'motion.content.shadow.ios.radius');
    }
    if (contentShadow?.ios != null) {
      const offset = contentShadow.ios.offset;
      if (offset != null) {
        if (!Number.isFinite(offset.x)) throw new RangeError('motion.content.shadow.ios.offset.x must be finite.');
        if (!Number.isFinite(offset.y)) throw new RangeError('motion.content.shadow.ios.offset.y must be finite.');
      }
    }
    const springMass = interaction?.spring?.mass ?? DEFAULT_SPRING_MASS;
    const springStiffness = interaction?.spring?.stiffness ?? DEFAULT_SPRING_STIFFNESS;
    const springDamping = interaction?.spring?.damping ?? DEFAULT_SPRING_DAMPING;
    const releaseOpenThreshold = interaction?.release?.openThreshold ?? DEFAULT_RELEASE_OPEN_THRESHOLD;
    const releaseVelocitySensitivity = interaction?.release?.velocitySensitivity ?? DEFAULT_RELEASE_VELOCITY_SENSITIVITY;
    const releaseVelocityTransfer = interaction?.release?.velocityTransfer ?? DEFAULT_RELEASE_VELOCITY_TRANSFER;
    const overdrag = interaction?.overdrag ?? DEFAULT_OVERDRAG;
    requirePositiveFinite(springMass, 'interaction.spring.mass');
    requirePositiveFinite(springStiffness, 'interaction.spring.stiffness');
    requirePositiveFinite(springDamping, 'interaction.spring.damping');
    requireFiniteSpringDynamics(springMass, springStiffness, springDamping);
    requireUnitInterval(releaseOpenThreshold, 'interaction.release.openThreshold');
    requireNonNegativeFinite(releaseVelocitySensitivity, 'interaction.release.velocitySensitivity');
    requireNonNegativeFinite(releaseVelocityTransfer, 'interaction.release.velocityTransfer');
    requireNonNegativeFinite(overdrag, 'interaction.overdrag');
    const motionConfig = this.motionConfigFor(motion);

    // Reanimated Paper subscriptions use RN's normalized top* event name.
    void topProgress;

    return (
      <NativeSideDrawerView
        {...props}
        contentBorderColor={contentBorder?.color ?? 'transparent'}
        contentBorderWidth={contentBorder == null ? 0 : (contentBorder.width ?? 1)}
        contentCornerRadius={contentCornerRadius ?? -1}
        contentShadowColor={contentShadow?.color ?? 'transparent'}
        contentShadowElevation={contentShadow == null ? 0 : (contentShadow.android?.elevation ?? DEFAULT_ANDROID_SHADOW_ELEVATION)}
        contentShadowOffsetX={contentShadow?.ios?.offset?.x ?? 0}
        contentShadowOffsetY={contentShadow?.ios?.offset?.y ?? 0}
        contentShadowRadius={contentShadow == null ? 0 : (contentShadow.ios?.radius ?? DEFAULT_IOS_SHADOW_RADIUS)}
        drawerWidth={drawerWidth}
        gestureEnabled={gestureEnabled}
        gestureReleaseHaptic={gestureReleaseHaptic}
        initialOpen={initialOpen}
        motionConfig={motionConfig}
        overdrag={overdrag}
        onProgress={onProgress}
        onTransitionEnd={onTransitionEnd || onOpenChange ? this.handleTransitionEnd : undefined}
        onTransitionStart={onTransitionStart ? this.handleTransitionStart : undefined}
        overlayColor={motion?.overlay?.color ?? 'transparent'}
        progressEventsEnabled={onProgress != null || topProgress != null}
        releaseOpenThreshold={releaseOpenThreshold}
        releaseVelocitySensitivity={releaseVelocitySensitivity}
        releaseVelocityTransfer={releaseVelocityTransfer}
        ref={this.setNativeRef}
        side={side}
        springDamping={springDamping}
        springMass={springMass}
        springStiffness={springStiffness}
        transitionEndEventsEnabled={onTransitionEnd != null || onOpenChange != null}
        transitionStartEventsEnabled={onTransitionStart != null}
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
