import * as React from 'react';
import { StatusBar } from 'react-native';
import { ExampleApp } from './src/ExampleApp';

export default function App(): React.JSX.Element {
  return (
    <>
      <StatusBar barStyle="light-content" />
      <ExampleApp />
    </>
  );
}
