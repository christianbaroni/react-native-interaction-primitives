const path = require('path');
const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');

const appNodeModules = path.resolve(__dirname, 'node_modules');
const packageRoot = path.resolve(__dirname, '..');

const config = {
  resolver: {
    disableHierarchicalLookup: true,
    extraNodeModules: {
      react: path.resolve(appNodeModules, 'react'),
      'react-native': path.resolve(appNodeModules, 'react-native'),
      'react-native-pager-drawer': packageRoot,
    },
    nodeModulesPaths: [appNodeModules],
    unstable_enableSymlinks: true,
  },
  watchFolders: [packageRoot],
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
