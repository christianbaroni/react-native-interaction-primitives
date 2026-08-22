module.exports = {
  dependency: {
    platforms: {
      ios: {},
      android: {
        packageImportPath: 'import com.rninteractionprimitives.RNInteractionPrimitivesPackage;',
        packageInstance: 'new RNInteractionPrimitivesPackage()',
      },
    },
  },
};
