import 'dart:async';
import 'dart:convert';
import 'dart:io';

class WebSearchResult {
  const WebSearchResult({
    required this.title,
    required this.url,
    this.snippet = '',
  });
  final String title;
  final Uri url;
  final String snippet;
}

abstract interface class WebSearchSource {
  Future<List<WebSearchResult>> search(String query);
}

/// Fuente beta sin claves. DuckDuckGo puede cambiar su HTML: por eso la app
/// depende de esta interfaz, no de su estructura concreta.
class DuckDuckGoHtmlSource implements WebSearchSource {
  DuckDuckGoHtmlSource({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;
  final HttpClient Function() _clientFactory;

  @override
  Future<List<WebSearchResult>> search(String query) async {
    final client = _clientFactory();
    try {
      final request = await client.getUrl(
        Uri.https('html.duckduckgo.com', '/html/', {'q': query}),
      );
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'KRAFT/0.1 web-discovery',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('La búsqueda devolvió ${response.statusCode}.');
      }
      final html = await utf8.decoder.bind(response).join();
      final link = RegExp(
        r'class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
        dotAll: true,
      );
      final snippet = RegExp(
        r'class="result__snippet"[^>]*>(.*?)</(?:a|div)>',
        dotAll: true,
      );
      final snippets = snippet
          .allMatches(html)
          .map((m) => _plain(m.group(1) ?? ''))
          .toList();
      final results = <WebSearchResult>[];
      for (final (index, match) in link.allMatches(html).indexed.take(8)) {
        final raw = htmlDecode(match.group(1) ?? '');
        final uri = Uri.tryParse(raw);
        if (uri == null || !uri.hasScheme) {
          continue;
        }
        results.add(
          WebSearchResult(
            title: _plain(match.group(2) ?? ''),
            url: uri,
            snippet: index < snippets.length ? snippets[index] : '',
          ),
        );
      }
      return results;
    } finally {
      client.close(force: true);
    }
  }

  static String _plain(String value) => htmlDecode(
    value.replaceAll(RegExp(r'<[^>]+>'), ''),
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
  static String htmlDecode(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x27;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}

class WebSearchClient {
  WebSearchClient({WebSearchSource? source})
    : source = source ?? DuckDuckGoHtmlSource();
  final WebSearchSource source;
  Future<List<WebSearchResult>> search(String query) {
    final cleaned = query.trim();
    if (cleaned.isEmpty) return Future.value(const []);
    return source.search(cleaned);
  }
}
