import * as React from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Pager, type PagerRef } from 'react-native-pager-drawer';

const PAGES = [
  { color: '#C9E7FF', eyebrow: 'Native gesture', title: 'Interrupt any settle' },
  { color: '#D8F5D0', eyebrow: 'Bounded fling', title: 'One release, one page' },
  { color: '#FFE2C5', eyebrow: 'Platform motion', title: 'No JS frame loop' },
] as const;

export function PagerExample(): React.JSX.Element {
  const pagerRef = React.useRef<PagerRef>(null);
  const [page, setPage] = React.useState(1);

  const showPage = React.useCallback((nextPage: number) => {
    pagerRef.current?.setPage(nextPage);
  }, []);

  return (
    <View style={styles.root}>
      <View style={styles.header}>
        <Text style={styles.kicker}>REACT NATIVE PAGER DRAWER</Text>
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
            </View>
          </View>
        ))}
      </Pager>

      <View style={styles.controls}>
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
    paddingBottom: 32,
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
    paddingTop: 72,
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
