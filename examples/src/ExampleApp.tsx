import * as React from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { PagerExample } from './PagerExample';
import { SideDrawerExample } from './SideDrawerExample';

type Example = 'pager' | 'drawer';

export function ExampleApp(): React.JSX.Element {
  const [example, setExample] = React.useState<Example>('drawer');
  const navigation = (
    <View style={styles.switcher}>
      <ExampleButton active={example === 'pager'} label="Pager" onPress={() => setExample('pager')} />
      <ExampleButton active={example === 'drawer'} label="Side drawer" onPress={() => setExample('drawer')} />
    </View>
  );

  return (
    <SafeAreaProvider>
      <View style={styles.root}>
        {example === 'pager' ? <PagerExample navigation={navigation} /> : <SideDrawerExample navigation={navigation} />}
      </View>
    </SafeAreaProvider>
  );
}

function ExampleButton({ active, label, onPress }: { active: boolean; label: string; onPress(): void }) {
  return (
    <Pressable onPress={onPress} style={[styles.switcherButton, active && styles.switcherButtonActive]}>
      <Text style={[styles.switcherLabel, active && styles.switcherLabelActive]}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  root: {
    backgroundColor: '#0D1014',
    flex: 1,
  },
  switcher: {
    flexDirection: 'row',
    gap: 8,
  },
  switcherButton: {
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 9,
  },
  switcherButtonActive: {
    backgroundColor: '#252B34',
  },
  switcherLabel: {
    color: '#788391',
    fontSize: 13,
    fontWeight: '700',
  },
  switcherLabelActive: {
    color: '#F5F7FA',
  },
});
