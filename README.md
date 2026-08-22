# react-native-interaction-primitives

Native interaction primitives for React Native. The package currently provides an interruptible pager and underlay side drawer. Gestures, release projection, and animations remain on the platform UI thread; JavaScript and Reanimated can observe motion without driving it.

The package supports React Native 0.81 and later. React Native 0.81 apps may use either Paper or Fabric. React Native 0.82 and later use Fabric.

## Install

```sh
yarn add react-native-interaction-primitives
cd ios && pod install
```

## Pager

`Pager` renders each non-null child as one page. A release can advance at most one page from its committed anchor, including when a second gesture interrupts an in-flight settle.

```tsx
import * as React from 'react';
import { Text, View } from 'react-native';
import { Pager, type PagerRef } from 'react-native-interaction-primitives';

export function Deck() {
  const pager = React.useRef<PagerRef>(null);

  return (
    <Pager initialPage={1} onPageChange={({ page }) => console.log(page)} pageInset={20} pageSpacing={12} ref={pager} style={{ flex: 1 }}>
      <View key="one">
        <Text>One</Text>
      </View>
      <View key="two">
        <Text>Two</Text>
      </View>
      <View key="three">
        <Text>Three</Text>
      </View>
    </Pager>
  );
}
```

Call `setPage` through the ref for programmatic navigation:

```ts
pager.current?.setPage(2);
pager.current?.setPage(0, { animated: false });
```

The target must be an integer within the currently mounted page range. Invalid targets throw before a native command is dispatched.

### Props

- `initialPage?: number` — page selected when the native view first lays out.
- `orientation?: 'horizontal' | 'vertical'` — defaults to `horizontal`.
- `pageInset?: number` — inset on both sides of the paging axis.
- `pageSpacing?: number` — space between adjacent pages.
- `scrollEnabled?: boolean` — enables touch paging; imperative navigation remains available.
- `onPageChange?: ({ page }) => void` — reports the settled page when a settle completes.
- `onStateChange?: (state) => void` — reports the native phase transition model.
- `onPageScroll?: (event) => void` — reports continuous native position. The native implementations skip per-frame event construction when this prop is absent.

`Pager` also accepts React Native `ViewProps`.

### Native state

`onStateChange` reports one of four phases:

- `empty`
- `idle`, with the settled page
- `dragging`, with the gesture anchor page and offset
- `settling`, with the anchor, target, and `release` or `programmatic` source

`onPageScroll` receives the flat native transport, including `offset`, `position`, `page`, `pageCount`, `pageExtent`, `phase`, and the current anchor and target.

### Pager gesture ownership

A touched React Native scroll view on the pager's axis keeps a gesture while it can scroll in that exact direction. At an exhausted edge, a new same-axis gesture can move the pager instead of overscrolling the child. Cross-axis gestures remain with the touched content. Child-owned momentum cannot drive the pager, and a swipe that changes pages cannot later activate the control beneath it.

Custom React Native Gesture Handler relationships remain explicit. Compose the pager as an RNGH [`Native` gesture](https://docs.swmansion.com/react-native-gesture-handler/docs/gestures/use-native-gesture/) and make a child gesture block that native gesture when the child must take precedence (`blocksExternalGesture` in RNGH 2, `block` in RNGH 3). The package does not infer custom-handler intent from Android's undifferentiated interception signal, and it does not require RNGH when the app does not use it.

## Side drawer

`SideDrawer` keeps its drawer slot fixed underneath one moving application surface. Directionally valid horizontal gestures can open or close it from anywhere in the component while taps and cross-axis gestures remain with the touched content. A touched React Native horizontal scroll view receives the gesture while it can scroll in that exact direction; at an exhausted edge, the drawer remains eligible instead of yielding to overscroll. Once the drawer wins, it interrupts momentum in touched vertical scroll content instead of waiting for deceleration to finish.

```tsx
import * as React from 'react';
import { Text, View } from 'react-native';
import { SideDrawer, type SideDrawerRef } from 'react-native-interaction-primitives';

export function Shell() {
  const drawer = React.useRef<SideDrawerRef>(null);

  return (
    <SideDrawer
      drawer={
        <View>
          <Text>Navigation</Text>
        </View>
      }
      drawerWidth={300}
      motion={{
        content: {
          border: {
            color: 'rgba(255, 255, 255, 0.3)',
            opacity: { inputRange: [0, 0.9], outputRange: [0, 1] },
            width: 1,
          },
          shadow: {
            color: 'rgba(0, 0, 0, 0.7)',
            opacity: { inputRange: [0, 0.9], outputRange: [0, 0.5] },
          },
        },
        drawer: {
          opacity: { inputRange: [0, 0.9], outputRange: [0.1, 1] },
          scale: { inputRange: [0, 0.9], outputRange: [0.94, 1] },
          translateX: { inputRange: [0, 1], outputRange: [-16, 0] },
        },
        overlay: {
          color: 'black',
          opacity: { inputRange: [0, 1], outputRange: [0, 0.4] },
        },
      }}
      ref={drawer}
      style={{ flex: 1 }}
    >
      <View style={{ flex: 1 }}>
        <Text onPress={() => drawer.current?.open()}>Open</Text>
      </View>
    </SideDrawer>
  );
}
```

The ref exposes `open`, `close`, and `toggle`; each accepts `{ animated?: boolean }`. Every animated command and release can be interrupted by the next eligible gesture.

### Props

- `drawer: ReactElement` — the fixed underlay content.
- `children: ReactElement` — the application surface that moves over the drawer.
- `contentCornerRadius?: number` — defaults to the native screen radius; set `0` to disable clipping. iOS uses a continuous corner curve.
- `drawerWidth: number` — required reveal distance and drawer layout width.
- `gestureEnabled?: boolean` — enables native drag gestures; commands and tap-to-close remain available.
- `gestureReleaseHaptic?: HapticFeedbackType` — triggers once when a released swipe commits a change from the gesture's open/closed origin. A swipe that returns to its origin, commands, taps, cancellation, initial state, and animation completion never trigger it.
- `initialOpen?: boolean` — selects the initial native endpoint without creating a controlled state loop.
- `interaction?: SideDrawerInteraction` — tunes the native spring, release intent, and endpoint resistance without moving frame ownership into JavaScript.
- `motion?: SideDrawerMotion` — declarative native interpolation for drawer/content opacity, uniform scale, `translateX`, `translateY`, pane border/shadow, and overlay color/opacity.
- `side?: 'start' | 'end'` — logical drawer side, resolved through native layout direction.
- `onOpenChange?: (open) => void` — reports a completed endpoint change.
- `onProgress?: (event) => void` — reports normalized progress and native phase. Both platforms skip payload construction when this observer is absent.

The default iOS screen radius reads the private `UIScreen` display-corner property and falls back to `0` if it is unavailable. Pass an explicit `contentCornerRadius` to avoid that private lookup when App Store policy is a concern. A component-owned native content host owns the mask, so React lifecycle updates cannot replace it. Android uses `WindowInsets.getRoundedCorner` on Android 12 and later and otherwise falls back to `0` unless an override is supplied.

`onProgress` reports `progress` in `[0, 1]`, `phase`, `targetOpen`, and the `release`, `programmatic`, or `none` settling source. Attaching an observer publishes the current native snapshot, including an `initialOpen` state that has not moved. It is observational; writing the event back into layout is not part of the component contract.

### Interaction

`interaction.spring` exposes the physical mass, stiffness, and damping coefficient used by released gestures and animated commands. Values must be finite and greater than zero. The default is the existing critically damped response:

```tsx
interaction={{
  spring: {
    mass: 1,
    stiffness: 483.61061565337855,
    damping: 43.982297150257104,
  },
}}
```

These are direct spring parameters, not duration or bounce aliases. Lower damping can create underdamped oscillation; critical and overdamped combinations are also supported. Zero damping is excluded because it never completes, while the drawer's settling phase must reach an endpoint.

Release intent and release motion are separate decisions:

```tsx
interaction={{
  release: {
    openThreshold: 0.5,
    velocitySensitivity: 1,
    velocityTransfer: 1,
  },
  overdrag: 4,
}}
```

`openThreshold` is the projected reveal progress that selects open and must be in `[0, 1]`. `velocitySensitivity` changes only endpoint selection: `0` ignores velocity, `1` preserves the accepted platform-native prediction, and larger values make decisive flings more influential. It is not an animation duration and does not need to track the spring.

`velocityTransfer` changes only how much mapped finger velocity the settling spring receives. `0` starts from rest, `1` requests a continuous release handoff, and values above `1` amplify release energy. The endpoint boundary can resist that energy when it would add more exterior travel than `overdrag` permits.

`overdrag` is measured in points on iOS and density-independent pixels on Android. It controls gesture-derived endpoint travel and defaults to `4`; `0` creates a hard, immediately reversible direct boundary. An underdamped spring's own natural overshoot is not clipped or rewritten by this setting.

Each admitted gesture snapshots the complete interaction configuration, including its release policy. Programmatic settling takes a fresh snapshot when it begins. Updating `interaction` never changes a gesture or settle already in progress; layout, pause, and resume retain that interaction's snapshot. Gesture input, target choice, settling, interruption, and retargeting remain native on Paper and Fabric.

Each motion channel has matching `inputRange` and `outputRange` arrays with at least two points. Inputs must be finite, strictly increasing, and within `[0, 1]`; outputs must be finite. Native evaluation clamps before the first input and after the last. Translation outputs use React Native layout units: points on iOS and density-independent pixels on Android.

`motion.content.border` draws above the application content and overlay while inheriting the pane's native corner mask and full-screen transform origin. `color` is required, `width` is measured in React Native layout units and defaults to `1`, and `opacity` is an optional motion interpolation. A missing border has zero width and adds no motion channel.

`motion.content.shadow` casts behind the moving pane from a fixed native rounded path. `color` is required; its alpha sets the shadow's static strength, and the optional `opacity` interpolation multiplies that strength over reveal progress. When a shadow is present, iOS `radius` and Android `elevation` each default to `16`; explicit `0` disables the shadow on that platform. Override platform geometry without changing the common motion channel:

```tsx
shadow: {
  color: 'rgba(0, 0, 0, 0.7)',
  opacity: { inputRange: [0, 0.9], outputRange: [0, 0.5] },
  ios: { radius: 20, offset: { x: -3, y: 0 } },
  android: { elevation: 18 },
}
```

iOS radius and offset use points; Android elevation uses density-independent pixels. Android 7.0–8.1 applies the requested color alpha to the platform's black elevation shadow; custom RGB shadow hue is available on Android 9 and later. The caster path/outline is rebuilt only when pane geometry changes, while animated opacity remains a compositor property. It does not snapshot or rasterize application content.

Drawer transforms are applied to a full-screen native underlay host, so scale and translation keep a stable screen-relative origin throughout reveal. `drawerWidth` still owns both reveal distance and the caller drawer content's layout width.

The motion description is validated and flattened once per `motion` object, then compiled into native line segments when that prop changes. Direct manipulation evaluates those segments synchronously from reveal progress. During an iOS settle, UIKit owns the primary pane animation and a native display observer derives only the configured secondary transforms, opacity, and overlay from the pane's presented reveal. Android evaluates primary and secondary motion together in its native frame callback. Native motion evaluation does not require React renders, JavaScript, Reanimated worklets, or layout passes; attaching `onProgress` separately opts into native event delivery. Overlay color is constant for a motion description; its opacity is interpolated.

`HapticFeedbackType` is `selection`, `light`, `medium`, `heavy`, `soft`, `rigid`, `success`, `warning`, or `error`. These names match the native iOS feedback families. Android maps them to the closest available system feedback and respects the user's system haptic settings. iOS prepares the configured generator on contact and again when a valid drag begins, then triggers it synchronously when release target selection commits a change.

| Type                         | Android feedback                                           |
| ---------------------------- | ---------------------------------------------------------- |
| `selection`                  | segment tick on Android 14+, clock tick otherwise          |
| `soft`                       | frequent segment tick on Android 14+, clock tick otherwise |
| `light` / `medium` / `heavy` | keyboard tap / virtual key / long press                    |
| `rigid`                      | context click                                              |
| `success`                    | confirm on Android 11+, virtual key otherwise              |
| `warning`                    | context click                                              |
| `error`                      | reject on Android 11+, long press otherwise                |

## Reanimated observation

Reanimated is optional and lives behind the `react-native-interaction-primitives/reanimated` entry point. The hooks update shared values from direct native progress events. They do not schedule or advance native animation.

```tsx
import Animated from 'react-native-reanimated';
import { Pager } from 'react-native-interaction-primitives';
import { usePager } from 'react-native-interaction-primitives/reanimated';

const AnimatedPager = Animated.createAnimatedComponent(Pager);

function Deck() {
  const pager = usePager();

  return (
    <AnimatedPager ref={pager.ref} onPageScroll={pager.onPageScroll}>
      {/* pages */}
    </AnimatedPager>
  );
}
```

The controller exposes `offset`, `page`, `phase`, and `position` shared values, plus the ordinary `setPage` command and pager ref.

`useSideDrawer` follows the same observation-only contract:

```tsx
import Animated from 'react-native-reanimated';
import { SideDrawer } from 'react-native-interaction-primitives';
import { useSideDrawer } from 'react-native-interaction-primitives/reanimated';

const AnimatedSideDrawer = Animated.createAnimatedComponent(SideDrawer);

function Shell() {
  const drawer = useSideDrawer();

  return (
    <AnimatedSideDrawer drawer={/* drawer content */} drawerWidth={300} onProgress={drawer.onProgress} ref={drawer.ref}>
      {/* application content */}
    </AnimatedSideDrawer>
  );
}
```

The controller exposes `progress`, `phase`, `settlingSource`, and `targetOpen` shared values, plus ordinary `open`, `close`, and `toggle` commands and the drawer ref. Use the `motion` prop for visuals that must remain native even when no observer is attached.

## Motion ownership

On iOS, `UIScrollView` owns full-surface touch arbitration, but its content offset and bounce physics do not own settling. A `UIViewPropertyAnimator` spring moves the native content host directly. On Android, the native parent owns directional interception and `Choreographer` advances the same damped-spring equation. Both platforms choose the endpoint with native velocity projection and apply the configured release and boundary policy before starting the spring. An outward gesture cannot begin from the closed endpoint; after a valid gesture has moved inward, reversal into either endpoint uses the same bounded resistance.

Core Animation owns iOS pane presentation and receives system-managed ProMotion pacing. A `CADisplayLink` exists only while configured secondary motion, progress observation, or touch-pause resumption requires it; it samples the presented pane once and never advances primary motion. Android advances from `Choreographer.FrameCallback.frameTimeNanos` and requests the high frame-rate category on Android 15 and later. Neither implementation waits on JavaScript or Reanimated to produce a frame.

For 120 Hz updates on supported iPhones, the host application must set `CADisableMinimumFrameDurationOnPhone` to `true`. Actual refresh cadence remains subject to the display, host configuration, Low Power Mode, and system thermal policy.

## License

MIT
