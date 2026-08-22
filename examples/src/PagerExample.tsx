import * as React from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Pager, type PagerRef } from 'react-native-interaction-primitives';

const PAGES = [
  { color: '#C9E7FF', eyebrow: 'Native gesture', title: 'Interrupt any settle' },
  { color: '#D8F5D0', eyebrow: 'Nested ownership', title: 'Scroll here, page at the edge' },
  { color: '#FFE2C5', eyebrow: 'Platform motion', title: 'No JS frame loop' },
] as const;

const NESTED_SCROLL_CARDS = ['First edge', 'Inner range', 'Still scrolling', 'Last edge'] as const;

export function PagerExample({ navigation }: { navigation: React.ReactNode }): React.JSX.Element {
  const pagerRef = React.useRef<PagerRef>(null);
  const insets = useSafeAreaInsets();
  const [page, setPage] = React.useState(1);
  const [tapCount, setTapCount] = React.useState(0);

  const showPage = React.useCallback((nextPage: number) => {
    pagerRef.current?.setPage(nextPage);
  }, []);

  return (
    <View style={styles.root}>
      <View style={[styles.navigation, { paddingTop: insets.top + 14 }]}>{navigation}</View>
      <View style={styles.header}>
        <Text style={styles.kicker}>REACT NATIVE INTERACTION PRIMITIVES</Text>
        <Text style={styles.heading}>Native pager</Text>
        <Text style={styles.detail}>Drag, fling, then grab the page again while it is still moving.</Text>
      </View>

      <Pager
        initialPage={1}
        onPageChange={event => setPage(event.page)}
        pageInset={20}
        pageSpacing={12}
        ref={pagerRef}
        style={styles.pager}
      >
        {PAGES.map((item, index) => (
          <View key={item.title} style={[styles.page, { backgroundColor: item.color }]}>
            <Text style={styles.pageNumber}>0{index + 1}</Text>
            <View>
              <Text style={styles.eyebrow}>{item.eyebrow}</Text>
              <Text style={styles.title}>{item.title}</Text>
              {index === 1 ? (
                <>
                  <ScrollView
                    accessibilityLabel="Nested pager scroll gesture probe"
                    contentContainerStyle={styles.nestedCards}
                    directionalLockEnabled
                    horizontal
                    nestedScrollEnabled
                    showsHorizontalScrollIndicator={false}
                    style={styles.nestedScroll}
                  >
                    {NESTED_SCROLL_CARDS.map(label => (
                      <View key={label} style={styles.nestedCard}>
                        <Text style={styles.nestedCardText}>{label}</Text>
                      </View>
                    ))}
                  </ScrollView>
                  <Pressable
                    accessibilityRole="button"
                    onPress={() => setTapCount(count => count + 1)}
                    style={({ pressed }) => [styles.tapProbe, pressed && styles.tapProbePressed]}
                  >
                    <Text style={styles.tapProbeText}>Tap target · {tapCount}</Text>
                  </Pressable>
                </>
              ) : null}
            </View>
          </View>
        ))}
      </Pager>

      <View style={[styles.controls, { paddingBottom: Math.max(20, insets.bottom + 8) }]}>
        <Pressable disabled={page === 0} onPress={() => showPage(page - 1)} style={styles.button}>
          <Text style={[styles.buttonText, page === 0 && styles.disabled]}>Previous</Text>
        </Pressable>
        <Text style={styles.position}>
          {page + 1} / {PAGES.length}
        </Text>
        <Pressable disabled={page === PAGES.length - 1} onPress={() => showPage(page + 1)} style={styles.button}>
          <Text style={[styles.buttonText, page === PAGES.length - 1 && styles.disabled]}>Next</Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  button: {
    paddingHorizontal: 8,
    paddingVertical: 12,
  },
  buttonText: {
    color: '#F5F7FA',
    fontSize: 16,
    fontWeight: '600',
  },
  controls: {
    alignItems: 'center',
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
  },
  detail: {
    color: '#9BA3AE',
    fontSize: 16,
    lineHeight: 23,
    marginTop: 8,
    maxWidth: 340,
  },
  disabled: {
    opacity: 0.28,
  },
  eyebrow: {
    color: '#20242A',
    fontSize: 14,
    fontWeight: '700',
    letterSpacing: 0.8,
    textTransform: 'uppercase',
  },
  header: {
    paddingHorizontal: 20,
    paddingTop: 52,
  },
  heading: {
    color: '#F5F7FA',
    fontSize: 36,
    fontWeight: '700',
    letterSpacing: -1.2,
    marginTop: 8,
  },
  kicker: {
    color: '#7DFFB2',
    fontSize: 12,
    fontWeight: '800',
    letterSpacing: 1.4,
  },
  navigation: {
    paddingBottom: 10,
    paddingHorizontal: 12,
  },
  nestedCard: {
    alignItems: 'center',
    backgroundColor: '#B9DDB0',
    borderRadius: 14,
    justifyContent: 'center',
    minHeight: 52,
    paddingHorizontal: 16,
  },
  nestedCards: {
    gap: 8,
    paddingRight: 20,
  },
  nestedCardText: {
    color: '#254126',
    fontSize: 13,
    fontWeight: '700',
  },
  nestedScroll: {
    marginRight: -28,
    marginTop: 18,
  },
  page: {
    borderRadius: 28,
    justifyContent: 'space-between',
    padding: 28,
  },
  pageNumber: {
    color: '#20242A',
    fontSize: 72,
    fontWeight: '300',
    letterSpacing: -4,
    opacity: 0.34,
  },
  pager: {
    flex: 1,
    marginVertical: 28,
  },
  position: {
    color: '#9BA3AE',
    fontSize: 14,
    fontVariant: ['tabular-nums'],
  },
  root: {
    backgroundColor: '#101318',
    flex: 1,
  },
  tapProbe: {
    alignItems: 'center',
    alignSelf: 'flex-start',
    backgroundColor: '#254126',
    borderRadius: 13,
    justifyContent: 'center',
    marginTop: 12,
    minHeight: 44,
    paddingHorizontal: 16,
  },
  tapProbePressed: {
    opacity: 0.84,
    transform: [{ scale: 0.96 }],
  },
  tapProbeText: {
    color: '#F3FFF1',
    fontSize: 13,
    fontWeight: '700',
  },
  title: {
    color: '#20242A',
    fontSize: 32,
    fontWeight: '700',
    letterSpacing: -1,
    lineHeight: 36,
    marginTop: 8,
    maxWidth: 260,
  },
});
