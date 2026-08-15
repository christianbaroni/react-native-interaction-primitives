import { codegenNativeComponent, type ViewProps } from 'react-native';

// Codegen requires component props to be declared as a named interface.
// eslint-disable-next-line @typescript-eslint/no-empty-object-type
export interface NativeProps extends ViewProps {}

export default codegenNativeComponent<NativeProps>('RNSideDrawerContentView');
