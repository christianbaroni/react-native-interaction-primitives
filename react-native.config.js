module.exports = {
  dependency: {
    platforms: {
      ios: {},
      android: {
        packageImportPath: 'import com.rnpagerdrawer.RNPagerPackage;',
        packageInstance: 'new RNPagerPackage()',
      },
    },
  },
};
