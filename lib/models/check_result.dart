enum Verdict { real, fake, uncertain }

class SearchSource {
  final String title;
  final String url;
  final String snippet;

  const SearchSource({
    required this.title,
    required this.url,
    required this.snippet,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'snippet': snippet,
      };

  factory SearchSource.fromJson(Map<String, dynamic> json) => SearchSource(
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
        snippet: json['snippet'] as String? ?? '',
      );
}

class CheckResult {
  final Verdict verdict;
  final double confidence;
  final String extractedText;
  final String summary;
  final List<SearchSource> sources;

  const CheckResult({
    required this.verdict,
    required this.confidence,
    required this.extractedText,
    required this.summary,
    required this.sources,
  });
}
