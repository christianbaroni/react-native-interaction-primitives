type NativeCommandCall = Readonly<{
  args: readonly unknown[];
  name: string;
}>;

type NativeCommand = (...args: unknown[]) => void;

const calls: NativeCommandCall[] = [];

export function __clearNativeCommandCalls(): void {
  calls.length = 0;
}

export function __getNativeCommandCalls(): readonly NativeCommandCall[] {
  return calls;
}

export function codegenNativeCommands(config: { supportedCommands: readonly string[] }): Readonly<Record<string, NativeCommand>> {
  const commands: Record<string, NativeCommand> = {};
  for (const name of config.supportedCommands) {
    commands[name] = (...args) => {
      calls.push({ args, name });
    };
  }
  return commands;
}
