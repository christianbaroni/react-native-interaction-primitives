import * as React from 'react';
import { Pressable, StyleSheet, Text, useWindowDimensions, View } from 'react-native';
import { SideDrawer, type SideDrawerRef } from 'react-native-pager-drawer';

const MENU_ITEMS = ['Library', 'Projects', 'Scheduled', 'Remote', 'Settings'] as const;

export function SideDrawerExample(): React.JSX.Element {
  const drawerRef = React.useRef<SideDrawerRef>(null);
  const { width } = useWindowDimensions();
  const [open, setOpen] = React.useState(false);
  const drawerWidth = Math.min(360, width * 0.76);

  return (
    <SideDrawer
      drawer={
        <View style={styles.drawer}>
          <Text style={styles.drawerTitle}>Native drawer</Text>
          <View style={styles.menu}>
            {MENU_ITEMS.map((item, index) => (
              <View key={item} style={styles.menuItem}>
                <Text style={styles.menuIndex}>0{index + 1}</Text>
                <Text style={styles.menuLabel}>{item}</Text>
              </View>
            ))}
          </View>
          <Text style={styles.drawerHint}>Swipe the content edge or tap the content while open.</Text>
        </View>
      }
      drawerWidth={drawerWidth}
      onOpenChange={setOpen}
      ref={drawerRef}
      style={styles.root}
    >
      <View style={styles.content}>
        <View>
          <Text style={styles.kicker}>UNDERLAY COMPOSITION</Text>
          <Text style={styles.heading}>Side drawer</Text>
          <Text style={styles.detail}>
            The application surface moves. The drawer stays fixed underneath and receives input only where it is revealed.
          </Text>
        </View>

        <View style={styles.card}>
          <Text style={styles.cardLabel}>NATIVE MOTION</Text>
          <Text style={styles.cardTitle}>Fling, interrupt, reverse.</Text>
          <Text style={styles.cardBody}>No JavaScript or Reanimated frame loop participates in the gesture or settle.</Text>
        </View>

        <Pressable onPress={() => drawerRef.current?.toggle()} style={styles.openButton}>
          <Text style={styles.openButtonText}>{open ? 'Close drawer' : 'Open drawer'}</Text>
        </Pressable>
      </View>
    </SideDrawer>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: '#FFFFFF',
    borderColor: '#D8DDE5',
    borderRadius: 24,
    borderWidth: 1,
    padding: 24,
  },
  cardBody: {
    color: '#67717E',
    fontSize: 15,
    lineHeight: 22,
    marginTop: 10,
  },
  cardLabel: {
    color: '#52606F',
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 1.2,
  },
  cardTitle: {
    color: '#151A20',
    fontSize: 26,
    fontWeight: '700',
    letterSpacing: -0.6,
    marginTop: 10,
  },
  content: {
    backgroundColor: '#F2F5F8',
    flex: 1,
    justifyContent: 'space-between',
    padding: 24,
    paddingBottom: 36,
    paddingTop: 48,
  },
  detail: {
    color: '#697481',
    fontSize: 16,
    lineHeight: 23,
    marginTop: 12,
    maxWidth: 360,
  },
  drawer: {
    backgroundColor: '#0D1014',
    flex: 1,
    paddingHorizontal: 24,
    paddingTop: 48,
  },
  drawerHint: {
    color: '#7C8794',
    fontSize: 13,
    lineHeight: 19,
    marginTop: 'auto',
    paddingBottom: 36,
  },
  drawerTitle: {
    color: '#F6F8FA',
    fontSize: 28,
    fontWeight: '700',
    letterSpacing: -0.7,
  },
  heading: {
    color: '#151A20',
    fontSize: 38,
    fontWeight: '700',
    letterSpacing: -1.2,
    marginTop: 8,
  },
  kicker: {
    color: '#2563EB',
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 1.3,
  },
  menu: {
    gap: 8,
    marginTop: 34,
  },
  menuIndex: {
    color: '#596472',
    fontSize: 11,
    fontVariant: ['tabular-nums'],
    width: 28,
  },
  menuItem: {
    alignItems: 'center',
    borderRadius: 14,
    flexDirection: 'row',
    paddingHorizontal: 12,
    paddingVertical: 14,
  },
  menuLabel: {
    color: '#E8ECF1',
    fontSize: 18,
    fontWeight: '600',
  },
  openButton: {
    alignItems: 'center',
    backgroundColor: '#1769E0',
    borderRadius: 18,
    paddingVertical: 16,
  },
  openButtonText: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '700',
  },
  root: {
    flex: 1,
  },
});
