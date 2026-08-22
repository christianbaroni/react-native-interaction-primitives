import * as React from 'react';
import { Pressable, ScrollView, StyleSheet, Text, useWindowDimensions, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { SideDrawer, type SideDrawerInteraction, type SideDrawerMotion, type SideDrawerRef } from 'react-native-interaction-primitives';

const MENU_ITEMS = ['Library', 'Projects', 'Scheduled', 'Remote', 'Settings'] as const;

const HANDOFF_CARDS = [
  { accent: '#2563EB', label: 'First edge', detail: 'Swipe right here to open the drawer.' },
  { accent: '#8B5CF6', label: 'Inner range', detail: 'Horizontal movement stays with this row.' },
  { accent: '#E8793E', label: 'Still scrolling', detail: 'The drawer remains stationary.' },
  { accent: '#159A73', label: 'Last edge', detail: 'Swipe left here while open to close.' },
] as const;

type SpringSettings = Required<NonNullable<SideDrawerInteraction['spring']>>;

type ReleaseSettings = Required<NonNullable<SideDrawerInteraction['release']>>;

type InteractionSettings = Readonly<{
  spring: SpringSettings;
  release: ReleaseSettings;
  overdrag: number;
}>;

type NumericParameter = Readonly<{
  label: string;
  hint: string;
  minimum: number;
  maximum: number;
  step: number;
  fractionDigits: number;
}>;

type KeyedParameter<Key extends string> = NumericParameter & Readonly<{ key: Key }>;

const DEFAULT_SPRING: SpringSettings = {
  mass: 0.8,
  stiffness: 680,
  damping: 46,
};

const DEFAULT_RELEASE: ReleaseSettings = {
  openThreshold: 0.5,
  velocitySensitivity: 1,
  velocityTransfer: 1,
};

const DEFAULT_INTERACTION: InteractionSettings = {
  spring: DEFAULT_SPRING,
  release: DEFAULT_RELEASE,
  overdrag: 4,
};

const SPRING_PRESETS = [
  { label: 'Default', spring: DEFAULT_SPRING },
  { label: 'Snappy', spring: { mass: 1.2, stiffness: 650, damping: 52 } },
  { label: 'Snappier', spring: { mass: 1, stiffness: 845, damping: 58 } },
  { label: 'Crisp', spring: { mass: 0.8, stiffness: 620, damping: 42 } },
  { label: 'Light', spring: { mass: 0.7, stiffness: 620, damping: 42 } },
  { label: 'Weighty', spring: { mass: 1.8, stiffness: 500, damping: 58 } },
  { label: 'Bounce', spring: { mass: 1, stiffness: 420, damping: 22 } },
] as const satisfies readonly Readonly<{ label: string; spring: SpringSettings }>[];

const SPRING_CONTROLS: readonly KeyedParameter<keyof SpringSettings>[] = [
  {
    key: 'mass',
    label: 'Mass',
    hint: 'Inertia carried through the settle',
    minimum: 0.2,
    maximum: 3,
    step: 0.1,
    fractionDigits: 1,
  },
  {
    key: 'stiffness',
    label: 'Stiffness',
    hint: 'Force pulling toward the endpoint',
    minimum: 100,
    maximum: 900,
    step: 25,
    fractionDigits: 1,
  },
  {
    key: 'damping',
    label: 'Damping',
    hint: 'Energy removed from the spring',
    minimum: 4,
    maximum: 100,
    step: 2,
    fractionDigits: 1,
  },
];

const RELEASE_CONTROLS: readonly KeyedParameter<keyof ReleaseSettings>[] = [
  {
    key: 'openThreshold',
    label: 'Open threshold',
    hint: 'Projected progress that selects the open endpoint',
    minimum: 0,
    maximum: 1,
    step: 0.05,
    fractionDigits: 2,
  },
  {
    key: 'velocitySensitivity',
    label: 'Velocity sensitivity',
    hint: 'Release velocity influence on endpoint choice',
    minimum: 0,
    maximum: 2,
    step: 0.1,
    fractionDigits: 1,
  },
  {
    key: 'velocityTransfer',
    label: 'Velocity transfer',
    hint: 'Finger velocity carried into the settling spring',
    minimum: 0,
    maximum: 2,
    step: 0.1,
    fractionDigits: 1,
  },
];

const OVERDRAG_CONTROL: NumericParameter = {
  label: 'Overdrag',
  hint: 'Gesture-derived travel beyond either endpoint',
  minimum: 0,
  maximum: 12,
  step: 1,
  fractionDigits: 0,
};

const DRAWER_MOTION: SideDrawerMotion = {
  content: {
    border: {
      color: '#FFFFFF',
      opacity: { inputRange: [0, 1], outputRange: [0, 0.12] },
      width: 4 / 3,
    },
    shadow: {
      color: '#000000B3',
      opacity: { inputRange: [0, 1], outputRange: [0, 0.6] },
    },
  },
  drawer: {
    opacity: { inputRange: [0, 0.6], outputRange: [0.2, 1] },
    scale: { inputRange: [0, 1], outputRange: [0.9725, 1] },
  },
  overlay: {
    color: '#000000',
    opacity: { inputRange: [0, 1], outputRange: [0, 0.42] },
  },
};

export function SideDrawerExample({ navigation }: { navigation: React.ReactNode }): React.JSX.Element {
  const drawerRef = React.useRef<SideDrawerRef>(null);
  const { width } = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const [open, setOpen] = React.useState(false);
  const [selectedItem, setSelectedItem] = React.useState<(typeof MENU_ITEMS)[number]>('Library');
  const [interaction, setInteraction] = React.useState<InteractionSettings>(DEFAULT_INTERACTION);
  const drawerWidth = Math.min(360, width * 0.76);
  const { spring } = interaction;
  const dampingRatio = spring.damping / (2 * Math.sqrt(spring.stiffness * spring.mass));
  const naturalFrequency = Math.sqrt(spring.stiffness / spring.mass) / (2 * Math.PI);
  const springResponse = Math.abs(dampingRatio - 1) < 0.01 ? 'Critical' : dampingRatio < 1 ? 'Underdamped' : 'Overdamped';

  const changeSpring = (key: keyof SpringSettings, value: number) => {
    setInteraction(current => ({ ...current, spring: { ...current.spring, [key]: value } }));
  };

  const changeRelease = (key: keyof ReleaseSettings, value: number) => {
    setInteraction(current => ({ ...current, release: { ...current.release, [key]: value } }));
  };

  return (
    <SideDrawer
      drawer={
        <View style={[styles.drawer, { paddingBottom: Math.max(24, insets.bottom + 12), paddingTop: insets.top + 24 }]}>
          <Text style={styles.drawerTitle}>Native drawer</Text>
          <View style={styles.menu}>
            {MENU_ITEMS.map((item, index) => (
              <Pressable
                accessibilityRole="button"
                key={item}
                onPress={() => setSelectedItem(item)}
                style={({ pressed }) => [
                  styles.menuItem,
                  item === selectedItem && styles.menuItemSelected,
                  pressed && styles.menuItemPressed,
                ]}
              >
                <Text style={styles.menuIndex}>0{index + 1}</Text>
                <Text style={styles.menuLabel}>{item}</Text>
              </Pressable>
            ))}
          </View>
          <Text style={styles.drawerHint}>Swipe anywhere to close, or tap the content surface.</Text>
        </View>
      }
      drawerWidth={drawerWidth}
      gestureReleaseHaptic="selection"
      interaction={interaction}
      motion={DRAWER_MOTION}
      onOpenChange={setOpen}
      ref={drawerRef}
      style={styles.root}
    >
      <View style={styles.content}>
        <View style={[styles.contentHeader, { paddingTop: insets.top + 14 }]}>{navigation}</View>
        <ScrollView
          contentContainerStyle={[styles.contentBody, { paddingBottom: Math.max(32, insets.bottom + 20) }]}
          directionalLockEnabled
          showsVerticalScrollIndicator={false}
          style={styles.contentScroll}
        >
          <View>
            <Text style={styles.kicker}>NATIVE INTERACTION LAB</Text>
            <Text style={styles.heading}>Tune the interaction</Text>
            <Text style={styles.detail}>
              Change the spring, release intent, and endpoint resistance, then open, fling, reverse, or interrupt the drawer. Every settle
              remains native.
            </Text>
          </View>

          <View style={styles.metricsCard}>
            <View style={styles.metric}>
              <Text style={styles.metricLabel}>RESPONSE</Text>
              <Text adjustsFontSizeToFit minimumFontScale={0.76} numberOfLines={1} style={styles.metricValue}>
                {springResponse}
              </Text>
            </View>
            <View style={styles.metricDivider} />
            <View style={styles.metric}>
              <Text style={styles.metricLabel}>DAMPING RATIO</Text>
              <Text adjustsFontSizeToFit minimumFontScale={0.76} numberOfLines={1} style={styles.metricValue}>
                {dampingRatio.toFixed(2)}
              </Text>
            </View>
            <View style={styles.metricDivider} />
            <View style={styles.metric}>
              <Text style={styles.metricLabel}>FREQUENCY</Text>
              <Text adjustsFontSizeToFit minimumFontScale={0.76} numberOfLines={1} style={styles.metricValue}>
                {naturalFrequency.toFixed(1)} Hz
              </Text>
            </View>
          </View>

          <View style={styles.card}>
            <View style={styles.cardHeader}>
              <View style={styles.cardHeaderCopy}>
                <Text style={styles.cardLabel}>INTERACTION PARAMETERS</Text>
                <Text style={styles.cardTitle}>Live native tuning</Text>
              </View>
              <Text style={styles.drawerState}>{open ? 'OPEN' : 'CLOSED'}</Text>
            </View>

            <Text style={styles.controlGroupLabel}>SPRING PRESETS</Text>
            <View style={styles.presets}>
              {SPRING_PRESETS.map(preset => {
                const selected = springsEqual(spring, preset.spring);
                return (
                  <Pressable
                    accessibilityRole="button"
                    accessibilityState={{ selected }}
                    key={preset.label}
                    onPress={() => setInteraction(current => ({ ...current, spring: preset.spring }))}
                    style={({ pressed }) => [styles.preset, selected && styles.presetSelected, pressed && styles.controlPressed]}
                  >
                    <Text style={[styles.presetLabel, selected && styles.presetLabelSelected]}>{preset.label}</Text>
                  </Pressable>
                );
              })}
            </View>

            <Text style={styles.controlGroupLabel}>SPRING</Text>
            <View style={styles.parameters}>
              {SPRING_CONTROLS.map(control => (
                <NumericParameterControl
                  control={control}
                  key={control.key}
                  onChange={value => changeSpring(control.key, value)}
                  value={spring[control.key]}
                />
              ))}
            </View>

            <View style={styles.controlGroupDivider} />
            <Text style={styles.controlGroupLabel}>RELEASE</Text>
            <View style={styles.parameters}>
              {RELEASE_CONTROLS.map(control => (
                <NumericParameterControl
                  control={control}
                  key={control.key}
                  onChange={value => changeRelease(control.key, value)}
                  value={interaction.release[control.key]}
                />
              ))}
            </View>

            <View style={styles.controlGroupDivider} />
            <Text style={styles.controlGroupLabel}>ENDPOINT RESISTANCE</Text>
            <View style={styles.parameters}>
              <NumericParameterControl
                control={OVERDRAG_CONTROL}
                onChange={value => setInteraction(current => ({ ...current, overdrag: value }))}
                value={interaction.overdrag}
              />
            </View>

            <Text style={styles.cardBody}>
              Changes are captured by the next gesture or command; an active interaction is never retuned mid-flight.
            </Text>
          </View>

          <View style={styles.handoffSection}>
            <View style={styles.handoffHeader}>
              <Text style={styles.handoffTitle}>Nested horizontal scroll</Text>
              <Text style={styles.handoffBadge}>GESTURE PROBE</Text>
            </View>
            <Text style={styles.handoffDetail}>
              The row owns a drag while it can move in that direction. At an exhausted edge, the drawer stays eligible.
            </Text>
            <ScrollView
              accessibilityLabel="Nested horizontal scroll gesture probe"
              contentContainerStyle={styles.handoffCards}
              decelerationRate="fast"
              directionalLockEnabled
              horizontal
              nestedScrollEnabled
              showsHorizontalScrollIndicator={false}
            >
              {HANDOFF_CARDS.map(card => (
                <View key={card.label} style={styles.handoffCard}>
                  <View style={[styles.handoffAccent, { backgroundColor: card.accent }]} />
                  <Text style={styles.handoffCardLabel}>{card.label}</Text>
                  <Text style={styles.handoffCardDetail}>{card.detail}</Text>
                </View>
              ))}
            </ScrollView>
          </View>

          <Pressable
            accessibilityRole="button"
            onPress={() => drawerRef.current?.toggle()}
            style={({ pressed }) => [styles.openButton, pressed && styles.openButtonPressed]}
          >
            <Text style={styles.openButtonText}>{open ? 'Close and test again' : 'Open with these settings'}</Text>
          </Pressable>
        </ScrollView>
      </View>
    </SideDrawer>
  );
}

function springsEqual(left: SpringSettings, right: SpringSettings): boolean {
  return (
    Math.abs(left.mass - right.mass) < 0.001 &&
    Math.abs(left.stiffness - right.stiffness) < 0.001 &&
    Math.abs(left.damping - right.damping) < 0.001
  );
}

function NumericParameterControl({
  control,
  onChange,
  value,
}: {
  control: NumericParameter;
  onChange(value: number): void;
  value: number;
}): React.JSX.Element {
  const decreaseDisabled = value <= control.minimum;
  const increaseDisabled = value >= control.maximum;
  const formattedValue = value.toFixed(control.fractionDigits);
  const update = (delta: number) => {
    const nextValue = Math.min(control.maximum, Math.max(control.minimum, value + delta));
    onChange(Math.round(nextValue * 1000) / 1000);
  };

  return (
    <View style={styles.parameter}>
      <View style={styles.parameterCopy}>
        <Text style={styles.parameterLabel}>{control.label}</Text>
        <Text style={styles.parameterHint}>{control.hint}</Text>
      </View>
      <View style={styles.stepper}>
        <StepperButton
          accessibilityLabel={`Decrease ${control.label.toLowerCase()}, current value ${formattedValue}`}
          disabled={decreaseDisabled}
          label="−"
          onPress={() => update(-control.step)}
        />
        <Text style={styles.parameterValue}>{formattedValue}</Text>
        <StepperButton
          accessibilityLabel={`Increase ${control.label.toLowerCase()}, current value ${formattedValue}`}
          disabled={increaseDisabled}
          label="+"
          onPress={() => update(control.step)}
        />
      </View>
    </View>
  );
}

function StepperButton({
  accessibilityLabel,
  disabled,
  label,
  onPress,
}: {
  accessibilityLabel: string;
  disabled: boolean;
  label: string;
  onPress(): void;
}): React.JSX.Element {
  return (
    <Pressable
      accessibilityLabel={accessibilityLabel}
      accessibilityRole="button"
      accessibilityState={{ disabled }}
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [
        styles.stepperButton,
        disabled && styles.stepperButtonDisabled,
        pressed && !disabled && styles.controlPressed,
      ]}
    >
      <Text style={styles.stepperButtonLabel}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: '#FFFFFF',
    borderColor: '#D8DDE5',
    borderRadius: 24,
    borderWidth: 1,
    padding: 20,
  },
  cardBody: {
    color: '#67717E',
    fontSize: 13,
    lineHeight: 19,
    marginTop: 18,
  },
  cardHeader: {
    alignItems: 'flex-start',
    flexDirection: 'row',
  },
  cardHeaderCopy: {
    flex: 1,
  },
  cardLabel: {
    color: '#52606F',
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 1.2,
  },
  cardTitle: {
    color: '#151A20',
    fontSize: 24,
    fontWeight: '700',
    letterSpacing: -0.6,
    marginTop: 6,
  },
  controlGroupDivider: {
    backgroundColor: '#E2E7ED',
    height: StyleSheet.hairlineWidth,
    marginTop: 12,
  },
  controlGroupLabel: {
    color: '#7A8491',
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 0.9,
    marginTop: 20,
  },
  content: {
    backgroundColor: '#0D1014',
    flex: 1,
  },
  contentBody: {
    backgroundColor: '#F2F5F8',
    flexGrow: 1,
    gap: 20,
    padding: 24,
    paddingTop: 32,
  },
  contentHeader: {
    paddingBottom: 10,
    paddingHorizontal: 12,
  },
  contentScroll: {
    flex: 1,
  },
  detail: {
    color: '#697481',
    fontSize: 16,
    lineHeight: 23,
    marginTop: 12,
    maxWidth: 380,
  },
  drawer: {
    backgroundColor: '#0D1014',
    flex: 1,
    paddingHorizontal: 24,
  },
  drawerHint: {
    color: '#7C8794',
    fontSize: 13,
    lineHeight: 19,
    marginTop: 'auto',
  },
  drawerTitle: {
    color: '#F6F8FA',
    fontSize: 28,
    fontWeight: '700',
    letterSpacing: -0.7,
  },
  heading: {
    color: '#151A20',
    fontSize: 36,
    fontWeight: '700',
    letterSpacing: -1.2,
    marginTop: 8,
  },
  handoffAccent: {
    borderRadius: 3,
    height: 6,
    width: 36,
  },
  handoffBadge: {
    color: '#657181',
    fontSize: 9,
    fontWeight: '800',
    letterSpacing: 0.8,
  },
  handoffCard: {
    backgroundColor: '#FFFFFF',
    borderColor: '#D8DDE5',
    borderRadius: 18,
    borderWidth: 1,
    minHeight: 126,
    padding: 16,
    width: 168,
  },
  handoffCardDetail: {
    color: '#74808E',
    fontSize: 12,
    lineHeight: 17,
    marginTop: 7,
  },
  handoffCardLabel: {
    color: '#1C2530',
    fontSize: 15,
    fontWeight: '700',
    marginTop: 15,
  },
  handoffCards: {
    gap: 10,
    paddingRight: 4,
  },
  handoffDetail: {
    color: '#697481',
    fontSize: 13,
    lineHeight: 19,
    marginTop: 8,
  },
  handoffHeader: {
    alignItems: 'center',
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  handoffSection: {
    backgroundColor: '#E7ECF2',
    borderRadius: 20,
    padding: 18,
  },
  handoffTitle: {
    color: '#1B222B',
    fontSize: 16,
    fontWeight: '700',
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
  menuItemPressed: {
    opacity: 0.72,
  },
  menuItemSelected: {
    backgroundColor: '#20262E',
  },
  menuLabel: {
    color: '#E8ECF1',
    fontSize: 18,
    fontWeight: '600',
  },
  metric: {
    flex: 1,
    minWidth: 0,
  },
  openButton: {
    alignItems: 'center',
    backgroundColor: '#1769E0',
    borderRadius: 18,
    minHeight: 56,
    justifyContent: 'center',
    paddingHorizontal: 20,
  },
  openButtonPressed: {
    opacity: 0.9,
    transform: [{ scale: 0.96 }],
  },
  openButtonText: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '700',
  },
  root: {
    flex: 1,
  },
  controlPressed: {
    opacity: 0.82,
    transform: [{ scale: 0.96 }],
  },
  drawerState: {
    backgroundColor: '#EDF2F7',
    borderRadius: 10,
    color: '#52606F',
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 0.9,
    overflow: 'hidden',
    paddingHorizontal: 9,
    paddingVertical: 7,
  },
  metricDivider: {
    alignSelf: 'stretch',
    backgroundColor: '#D9E0E8',
    width: StyleSheet.hairlineWidth,
  },
  metricLabel: {
    color: '#7A8491',
    fontSize: 9,
    fontWeight: '800',
    letterSpacing: 0.8,
  },
  metricsCard: {
    backgroundColor: '#E7ECF2',
    borderRadius: 18,
    flexDirection: 'row',
    gap: 14,
    justifyContent: 'space-between',
    paddingHorizontal: 18,
    paddingVertical: 16,
  },
  metricValue: {
    color: '#1C2632',
    fontSize: 14,
    fontVariant: ['tabular-nums'],
    fontWeight: '700',
    marginTop: 5,
  },
  parameter: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 12,
    minHeight: 66,
  },
  parameterCopy: {
    flex: 1,
  },
  parameterHint: {
    color: '#7B8591',
    fontSize: 11,
    lineHeight: 15,
    marginTop: 3,
  },
  parameterLabel: {
    color: '#1B222B',
    fontSize: 14,
    fontWeight: '700',
  },
  parameters: {
    marginTop: 12,
  },
  parameterValue: {
    color: '#1B222B',
    fontSize: 14,
    fontVariant: ['tabular-nums'],
    fontWeight: '700',
    minWidth: 52,
    textAlign: 'center',
  },
  preset: {
    alignItems: 'center',
    backgroundColor: '#EDF1F5',
    borderRadius: 12,
    justifyContent: 'center',
    minHeight: 44,
    paddingHorizontal: 13,
  },
  presetLabel: {
    color: '#586473',
    fontSize: 12,
    fontWeight: '700',
  },
  presetLabelSelected: {
    color: '#FFFFFF',
  },
  presets: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    marginTop: 10,
  },
  presetSelected: {
    backgroundColor: '#1769E0',
  },
  stepper: {
    alignItems: 'center',
    backgroundColor: '#EDF1F5',
    borderRadius: 14,
    flexDirection: 'row',
    overflow: 'hidden',
  },
  stepperButton: {
    alignItems: 'center',
    height: 44,
    justifyContent: 'center',
    width: 44,
  },
  stepperButtonDisabled: {
    opacity: 0.24,
  },
  stepperButtonLabel: {
    color: '#27313D',
    fontSize: 20,
    fontWeight: '500',
    marginTop: -1,
  },
});
