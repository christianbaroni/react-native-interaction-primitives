# react-native-pager-drawer

Native, interruptible paging for React Native. Gestures, release projection, and settle animations remain on the platform UI thread; JavaScript and Reanimated can observe motion without driving it.

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

## Reanimated observation

Reanimated is optional and lives behind the `react-native-pager-drawer/reanimated` entry point. The hook updates shared values from the pager's direct native scroll event. It does not schedule or advance the pager animation.

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

## Motion ownership

On iOS, `UIScrollView` handles direct manipulation and `UIViewPropertyAnimator` handles interrupted release snaps. On Android, touch arbitration, `VelocityTracker`, and `OverScroller` own the equivalent path. Neither implementation waits on JavaScript or Reanimated to produce a frame.

## License

MIT
