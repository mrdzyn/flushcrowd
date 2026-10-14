/// Defines runtime environments for FlushCrowd.
enum Environment {
  development,
  staging,
  production,
  unknown;

  static Environment fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'production':
      case 'prod':
        return Environment.production;
      case 'staging':
      case 'stage':
        return Environment.staging;
      case 'development':
      case 'dev':
        return Environment.development;
      default:
        return Environment.unknown;
    }
  }

  bool get isProduction => this == Environment.production;
  bool get isDevelopment => this == Environment.development;
  bool get isStaging => this == Environment.staging;
  bool get isUnknown => this == Environment.unknown;
}
