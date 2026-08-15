import * as React from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { PagerExample } from './PagerExample';
import { SideDrawerExample } from './SideDrawerExample';

type Example = 'pager' | 'drawer';

export function ExampleApp(): React.JSX.Element {
  const [example, setExample] = React.useState<Example>('drawer');

  return (
    <View style={styles.root}>
      <View style={styles.switcher}>
        <ExampleButton active={example === 'pager'} label="Pager" onPress={() => setExample('pager')} />
        <ExampleButton active={example === 'drawer'} label="Side drawer" onPress={() => setExample('drawer')} />
      </View>
      <View style={styles.stage}>{example === 'pager' ? <PagerExample /> : <SideDrawerExample />}</View>
    </View>
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
  stage: {
    flex: 1,
  },
  switcher: {
    backgroundColor: '#0D1014',
    flexDirection: 'row',
    gap: 8,
    paddingBottom: 10,
    paddingHorizontal: 12,
    paddingTop: 14,
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
