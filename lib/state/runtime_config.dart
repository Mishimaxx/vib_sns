class StreetPassRuntimeConfig {
  const StreetPassRuntimeConfig({
    required this.usesMockService,
    required this.usesMockBle,
    required this.downloadUrl,
  });

  final bool usesMockService;
  final bool usesMockBle;
  final String downloadUrl;
}
