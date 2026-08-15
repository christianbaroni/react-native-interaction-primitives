type NativeCommandCall = Readonly<{
  args: readonly unknown[];
  name: string;
}>;

const calls: NativeCommandCall[] = [];

export function __clearNativeCommandCalls(): void {
  calls.length = 0;
}

export function __getNativeCommandCalls(): readonly NativeCommandCall[] {
  return calls;
}

export default function codegenNativeCommands<Commands>(config: { supportedCommands: readonly string[] }): Commands {
  const commands = Object.fromEntries(
    config.supportedCommands.map(name => [
      name,
      (...args: unknown[]) => {
        calls.push({ args, name });
      },
    ])
  );
  // The real Codegen transform proves this mapping; the test boundary can only
  // construct its runtime command names from the supplied manifest.
  // eslint-disable-next-line @typescript-eslint/consistent-type-assertions
  return commands as Commands;
}
