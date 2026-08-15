# react-native-pager-drawer

Native, interruptible paging and underlay drawers for React Native. Gestures, release projection, and settle animations remain on the platform UI thread; JavaScript and Reanimated can observe motion without driving it.

The package supports React Native 0.81 and later. React Native 0.81 apps may use either Paper or Fabric. React Native 0.82 and later use Fabric.

## Install

```sh
yarn add react-native-pager-drawer
cd ios && pod install
```

## Pager

`Pager` renders each non-null child as one page. A release can advance at most one page from its committed anchor, including when a second gesture interrupts an in-flight settle.

```tsx
import * as React from 'react';
import { Text, View } from 'react-native';
import { Pager, type PagerRef } from 'react-native-pager-drawer';

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

## Side drawer

`SideDrawer` keeps its drawer slot fixed underneath one moving application surface. Directionally valid horizontal gestures can open or close it from anywhere in the component while taps and cross-axis gestures remain with the touched content.

```tsx
import * as React from 'react';
import { Text, View } from 'react-native';
import { SideDrawer, type SideDrawerRef } from 'react-native-pager-drawer';

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
- `motion?: SideDrawerMotion` — declarative native interpolation for drawer/content opacity, uniform scale, `translateX`, `translateY`, and overlay color/opacity.
- `side?: 'start' | 'end'` — logical drawer side, resolved through native layout direction.
- `onOpenChange?: (open) => void` — reports a completed endpoint change.
- `onProgress?: (event) => void` — reports normalized progress and native phase. Both platforms skip payload construction when this observer is absent.

The default iOS screen radius reads the private `UIScreen` display-corner property and falls back to `0` if it is unavailable. Pass an explicit `contentCornerRadius` to avoid that private lookup when App Store policy is a concern. Android uses `WindowInsets.getRoundedCorner` on Android 12 and later and otherwise falls back to `0` unless an override is supplied.

`onProgress` reports `progress` in `[0, 1]`, `phase`, `targetOpen`, and the `release`, `programmatic`, or `none` settling source. It is observational; writing the event back into layout is not part of the component contract.

Each motion channel has matching `inputRange` and `outputRange` arrays with at least two points. Inputs must be finite, strictly increasing, and within `[0, 1]`; outputs must be finite. Native evaluation clamps before the first input and after the last. Translation outputs use React Native layout units: points on iOS and density-independent pixels on Android.

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

Reanimated is optional and lives behind the `react-native-pager-drawer/reanimated` entry point. The hooks update shared values from direct native progress events. They do not schedule or advance native animation.

```tsx
import Animated from 'react-native-reanimated';
import { Pager } from 'react-native-pager-drawer';
import { usePager } from 'react-native-pager-drawer/reanimated';

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
import { SideDrawer } from 'react-native-pager-drawer';
import { useSideDrawer } from 'react-native-pager-drawer/reanimated';

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

On iOS, `UIScrollView` owns full-surface touch arbitration, but its content offset and bounce physics do not own settling. A `UIViewPropertyAnimator` spring moves the native content host directly. On Android, the native parent owns directional interception and `Choreographer` advances the same fixed critical response. Both platforms choose the endpoint with their native velocity projection and admit release velocity continuously until the resulting critical trajectory would exceed the four-point/dp excursion bound. A release already at an endpoint is an inelastic hard stop. Closed-state gestures cannot move the content past closed.

Core Animation owns iOS pane presentation and receives system-managed ProMotion pacing. A `CADisplayLink` exists only while configured secondary motion, progress observation, or touch-pause resumption requires it; it samples the presented pane once and never advances primary motion. Android advances from `Choreographer.FrameCallback.frameTimeNanos` and requests the high frame-rate category on Android 15 and later. Neither implementation waits on JavaScript or Reanimated to produce a frame.

For 120 Hz updates on supported iPhones, the host application must set `CADisableMinimumFrameDurationOnPhone` to `true`. Actual refresh cadence remains subject to the display, host configuration, Low Power Mode, and system thermal policy.

## License

MIT
