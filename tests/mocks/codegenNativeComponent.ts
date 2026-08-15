import * as React from 'react';

type NativeComponentProps = Record<string, unknown> & {
  children?: React.ReactNode;
};

const renderLog: NativeComponentProps[] = [];

export function __clearNativeComponentRenderLog(): void {
  renderLog.length = 0;
}

export function __getNativeComponentRenderLog(): NativeComponentProps[] {
  return renderLog;
}

export function __getLastNativeComponentProps(): NativeComponentProps {
  const props = renderLog.at(-1);
  if (props == null) throw new Error('No native component render has been recorded.');
  return props;
}

export default function codegenNativeComponent<Props extends NativeComponentProps>(
  name: string
): React.ForwardRefExoticComponent<React.PropsWithoutRef<Props> & React.RefAttributes<unknown>> {
  return React.forwardRef<unknown, Props>(function NativeComponent(props, ref) {
    const nativeRef = React.useMemo(() => ({ name }), []);
    React.useImperativeHandle(ref, () => nativeRef, [nativeRef]);
    renderLog.push({ '__native-ref': nativeRef, 'data-native-component': name, ...props });

    return React.createElement('rn-native-view', { 'data-native-component': name, ...props });
  });
}
