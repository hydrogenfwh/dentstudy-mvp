class BuildInfo {
  static const version =
      String.fromEnvironment('APP_VERSION', defaultValue: '1.1.2');
  static const builtAt =
      String.fromEnvironment('BUILD_TIME', defaultValue: '本地开发版');
}
