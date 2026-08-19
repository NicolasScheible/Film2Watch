/// Ein Streaming-Anbieter, bei dem ein Film im Abo verfügbar ist
/// (TMDB `/movie/{id}/watch/providers`, Feld `flatrate`).
class WatchProviderOption {
  const WatchProviderOption({
    required this.providerId,
    required this.providerName,
    required this.logoPath,
  });

  final int providerId;
  final String providerName;
  final String? logoPath;

  factory WatchProviderOption.fromTmdbJson(Map<String, dynamic> json) {
    return WatchProviderOption(
      providerId: (json['provider_id'] as num?)?.toInt() ?? 0,
      providerName: json['provider_name'] as String? ?? '',
      logoPath: json['logo_path'] as String?,
    );
  }
}
