import type { SideDrawerInterpolation, SideDrawerMotion } from './types';

const CHANNEL_COUNT = 10;
const EMPTY_CONFIG = Object.freeze(Array<number>(CHANNEL_COUNT).fill(0));

export function compileSideDrawerMotion(motion: SideDrawerMotion | undefined): readonly number[] {
  if (motion == null) return EMPTY_CONFIG;

  const channels: readonly (SideDrawerInterpolation | undefined)[] = [
    motion.drawer?.opacity,
    motion.drawer?.scale,
    motion.drawer?.translateX,
    motion.drawer?.translateY,
    motion.content?.opacity,
    motion.content?.scale,
    motion.content?.translateX,
    motion.content?.translateY,
    motion.overlay?.opacity,
    motion.content?.border?.opacity,
  ];

  const config = Array<number>(CHANNEL_COUNT).fill(0);

  channels.forEach((channel, channelIndex) => {
    if (channel == null) return;
    validateInterpolation(channel, channelIndex);
    config[channelIndex] = channel.inputRange.length;

    for (let pointIndex = 0; pointIndex < channel.inputRange.length; pointIndex += 1) {
      const input = channel.inputRange[pointIndex];
      const output = channel.outputRange[pointIndex];

      if (input == null || output == null) {
        throw new RangeError(`motion channel ${channelIndex} ranges must not contain missing points.`);
      }
      config.push(input, output);
    }
  });

  return config;
}

function validateInterpolation(interpolation: SideDrawerInterpolation, channel: number): void {
  const { inputRange, outputRange } = interpolation;

  if (inputRange.length < 2 || inputRange.length !== outputRange.length) {
    throw new RangeError(`motion channel ${channel} must have matching input and output ranges of at least two points.`);
  }

  let previousInput = -Infinity;

  for (const input of inputRange) {
    if (!Number.isFinite(input) || input < 0 || input > 1 || input <= previousInput) {
      throw new RangeError(`motion channel ${channel} inputRange must be finite, strictly increasing, and within [0, 1].`);
    }
    previousInput = input;
  }

  for (const output of outputRange) {
    if (!Number.isFinite(output)) {
      throw new RangeError(`motion channel ${channel} outputRange must contain only finite numbers.`);
    }
  }
}
