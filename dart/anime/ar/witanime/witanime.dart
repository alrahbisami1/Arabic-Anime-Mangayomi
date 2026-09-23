import 'package:mangayomi/bridge_lib.dart';
import 'dart:convert';

class WitAnime extends MProvider {
  WitAnime({required this.source});

  MSource source;

  final Client client =
      Client(source, '{"useDartHttpClient": true, "followRedirects": true}');
  final Client gateClient =
      Client(source, '{"useDartHttpClient": true, "followRedirects": false}');

  static const String domain = 'https://witanime.site';

  static const Map<String, String> browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36',
    'Accept-Language': 'ar,en;q=0.8',
  };

  String get baseUrl {
    final b = source.baseUrl ?? '';
    if (b.isEmpty || b.contains('witanime.you') || b.contains('witanime.net')) {
      return domain;
    }
    return b;
  }

  String abs(String url) => url.startsWith('http')
      ? url
      : '${baseUrl}${url.startsWith('/') ? '' : '/'}$url';

  int extractNumFromUrl(String url) {
    final last = substringAfterLast(url.replaceAll(RegExp(r'/$'), ''), '/');
    try {
      return int.tryParse(last) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  MManga? cardToManga(MElement card) {
    final href = card.attr('href') ?? '';
    if (href.isEmpty) return null;
    if (!href.contains('/anime/') && !href.contains('/movie/')) return null;
    final titleEl = card.selectFirst('h3');
    var title = (titleEl?.text ?? '').trim();
    if (title.isEmpty) {
      final img = card.selectFirst('img');
      title = Uri.decodeComponent(img?.attr('alt') ?? '').trim();
    }
    if (title.isEmpty) return null;
    final img = card.selectFirst('img');
    MManga anime = MManga();
    anime.name = title;
    anime.link = abs(href);
    anime.imageUrl = img?.attr('src') ?? '';
    return anime;
  }

  MPages parseCards(String html) {
    final doc = parseHtml(html);
    final list = <MManga>[];
    final seen = <String>{};
    for (var card in doc.select('a.group.block.w-full')) {
      final m = cardToManga(card);
      if (m != null && m.link.isNotEmpty && seen.add(m.link)) list.add(m);
    }
    return MPages(list, false);
  }

  @override
  Future<MPages> getPopular(int page) async {
    final url = '$baseUrl/browse${page > 1 ? '/page/$page' : ''}';
    final res = (await client.get(Uri.parse(url), headers: browserHeaders)).body;
    final pages = parseCards(res);
    pages.hasNextPage = RegExp('/browse/page/${page + 1}').hasMatch(res);
    return pages;
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    if (page > 1) return MPages([], false);
    final res = (await client.get(Uri.parse(baseUrl), headers: browserHeaders)).body;
    return parseCards(res);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    if (page > 1) return MPages([], false);
    final url = '$baseUrl/search?q=${Uri.encodeQueryComponent(query)}';
    final res = (await client.get(Uri.parse(url), headers: browserHeaders)).body;
    return parseCards(res);
  }

  @override
  Future<MManga> getDetail(String url) async {
    MManga anime = MManga();
    final res = (await client.get(Uri.parse(abs(url)), headers: browserHeaders)).body;
    final doc = parseHtml(res);
    anime.name =
        (doc.selectFirst('h1')?.text ??
                doc.selectFirst('meta[property="og:title"]')?.attr('content') ??
                '')
            .trim();
    anime.imageUrl =
        doc.selectFirst('meta[property="og:image"]')?.attr('content') ?? '';
    anime.description =
        doc.selectFirst('meta[property="og:description"]')?.attr('content') ?? '';
    List<MChapter> eps = [];
    final seen = <String>{};
    for (var a in doc.select('a[href*="/watch/"]')) {
      final href = abs(a.attr('href') ?? '');
      if (href.isEmpty || !seen.add(href)) continue;
      final n = extractNumFromUrl(href);
      MChapter ep = MChapter();
      ep.name = n > 0 ? 'الحلقة $n' : 'الحلقة ${eps.length + 1}';
      ep.url = href;
      eps.add(ep);
    }
    eps.sort((a, b) {
      final numA = extractNumFromUrl(a.url);
      final numB = extractNumFromUrl(b.url);
      return numA - numB;
    });
    anime.chapters = eps;
    return anime;
  }

  String extractCsrf(String html) {
    final m = RegExp(r'data-csrf="([^"]+)"').stringMatch(html);
    if (m == null) return '';
    return substringAfter(m, 'data-csrf="').replaceAll('"', '');
  }

  String headerValue(Map headers, String name) {
    for (final k in headers.keys) {
      if (k.toLowerCase() == name.toLowerCase()) {
        final v = headers[k];
        return v == null ? '' : v.toString();
      }
    }
    return '';
  }

  String extractCookies(Map headers) {
    final raw = headerValue(headers, 'set-cookie');
    if (raw.isEmpty) return '';
    final cookies = <String>[];
    final w = RegExp(r'witanime-session=[^;\s,]+').stringMatch(raw);
    if (w != null) cookies.add(w);
    final x = RegExp(r'XSRF-TOKEN=[^;\s,]+').stringMatch(raw);
    if (x != null) cookies.add(x);
    return cookies.join('; ');
  }

  String locationHeader(Map headers) => headerValue(headers, 'location');

  Future<String> resolveGate(String token, String referer, String csrf, String cookie) async {
    try {
      final r = await gateClient
          .get(
            Uri.parse('$baseUrl/watch/stream-gate/$token'),
            headers: {
              ...browserHeaders,
              'Accept': 'application/json',
              'X-CSRF-TOKEN': csrf,
              'Cookie': cookie,
              'Referer': referer,
            },
          )
          .timeout(Duration(seconds: 25));
      final loc = locationHeader(r.headers);
      if (loc.isNotEmpty && (loc.startsWith('http') || loc.startsWith('//'))) {
        return loc.startsWith('//') ? 'https:$loc' : loc;
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  String extractEmbedId(String embed) {
    final trimmed = embed.replaceAll(RegExp(r'/$'), '');
    final id = substringAfterLast(trimmed, '/e/');
    if (id.isEmpty || id == trimmed) return '';
    return substringBefore(id, '?').trim();
  }

  Future<String> fetchAudiniferEmbed(String id) async {
    try {
      final r = await client
          .get(
            Uri.parse('https://audinifer.com/e/$id'),
            headers: {
              ...browserHeaders,
              'Referer': 'https://witanime.site/',
            },
          )
          .timeout(Duration(seconds: 30));
      if (r.statusCode != 200) return '';
      return r.body;
    } catch (_) {
      return '';
    }
  }

  String extractHls(String unpacked, String key) {
    final token = '"$key":"';
    if (unpacked.contains(token)) {
      final rest = substringAfter(unpacked, token);
      final url = substringBefore(rest, '"').trim();
      if (url.startsWith('http')) return url;
    }
    return '';
  }

  Future<List<MVideo>> resolveHlsVideos(
      String embedUrl, String quality) async {
    final videos = <MVideo>[];
    try {
      final id = extractEmbedId(embedUrl);
      if (id.isEmpty) return videos;
      final html = await fetchAudiniferEmbed(id);
      if (html.isEmpty) return videos;
      final unpacked = unpackJsAndCombine(html) ?? '';
      if (unpacked.isEmpty) return videos;
      for (final key in ['hls3', 'hls2']) {
        final hls = extractHls(unpacked, key);
        if (hls.isEmpty) continue;
        videos.add(MVideo(hls, quality, hls, headers: {
          ...browserHeaders,
          'Referer': 'https://audinifer.com/',
        }));
      }
    } catch (_) {}
    return videos;
  }

  @override
  Future<List<MVideo>> getVideoList(String data) async {
    final url = abs(data.trim());
    if (url.isEmpty) return [];
    late String html;
    late Map watchHeaders;
    try {
      final watchRes = (await client
          .get(Uri.parse(url), headers: browserHeaders)
          .timeout(Duration(seconds: 25)));
      html = watchRes.body;
      watchHeaders = watchRes.headers;
    } catch (_) {
      return [];
    }
    if (html.isEmpty) return [];
    final csrf = extractCsrf(html);
    final cookie = extractCookies(watchHeaders);
    if (csrf.isEmpty) return [];
    String body = '';
    try {
      final postRes = await client
          .post(
            Uri.parse('$url/sources'),
            headers: {
              ...browserHeaders,
              'Accept': 'application/json',
              'X-CSRF-TOKEN': csrf,
              'Cookie': cookie,
              'Referer': url,
            },
          )
          .timeout(Duration(seconds: 25));
      if (postRes.statusCode == 200) {
        body = postRes.body;
      }
    } catch (_) {}
    if (body.isEmpty) return [];
    dynamic root;
    try {
      root = jsonDecode(body);
    } catch (_) {
      return [];
    }
    List<MVideo> videos = [];
    if (root is Map) {
      final players = root['players'];
      if (players is Map) {
        try {
          for (final q in players.keys) {
            final list = players[q];
            if (!(list is List)) continue;
            for (final item in list) {
              try {
                final map = item as Map;
                final token = map['token']?.toString() ?? '';
                final label = map['label']?.toString() ?? 'server';
                if (token.isEmpty || token == 'null') continue;
                final quality = '$q • $label';
                final embedUrl = await resolveGate(token, url, csrf, cookie);
                if (embedUrl.isEmpty) continue;
                final hlsVideos = await resolveHlsVideos(embedUrl, quality);
                if (hlsVideos.isNotEmpty) videos.addAll(hlsVideos);
              } catch (_) {}
            }
          }
        } catch (_) {}
      }
    }
    return videos;
  }
}

WitAnime main(MSource source) {
  return WitAnime(source: source);
}