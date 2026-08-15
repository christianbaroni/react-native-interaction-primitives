import codegenNativeComponent from './codegenNativeComponent';

export type HostComponent<Props> = (props: Props) => unknown;
export type ViewProps = Record<string, unknown>;

const nativeModules: Record<string, unknown> = {};

export const NativeModules = nativeModules;

export const TurboModuleRegistry = {
  get<T>(_name: string): T | null {
    return null;
  },
};

let nextTag = 1;
const tags = new WeakMap<object, number>();

export function findNodeHandle(value: object | null): number | null {
  if (value == null) return null;
  let tag = tags.get(value);
  if (tag == null) {
    tag = nextTag++;
    tags.set(value, tag);
  }
  return tag;
}

export function __getMockNodeHandle(value: object): number | null {
  return findNodeHandle(value);
}

export const StyleSheet = {
  create<T>(styles: T): T {
    return styles;
  },
};

export const Platform = {
  OS: 'ios',
  select<T>(values: { default?: T; ios?: T }) {
    return values.ios ?? values.default;
  },
};

export { codegenNativeComponent };

export function useWindowDimensions() {
  return { width: 390, height: 844, scale: 3, fontScale: 1 };
}

export function ScrollView(props: Record<string, unknown>) {
  return props;
}
