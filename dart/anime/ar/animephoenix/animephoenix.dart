import 'package:mangayomi/bridge_lib.dart';
import 'dart:convert';

class AnimePhoenix extends MProvider {
  AnimePhoenix({required this.source});

  MSource source;

  final Client client = Client();

  List<String>? _seen;

  String get baseUrl => source.baseUrl ?? '';

  String abs(String url) => url.startsWith('http')
      ? url
      : '${baseUrl}${url.startsWith('/') ? '' : '/'}$url';

  List<MManga> parseCards(MDocument doc, {bool latestOnly = false}) {
    List<MManga> list = [];
    final seen = <String>{};
    final scope = latestOnly
        ? doc.select('main.FJ-Phoenix-Anastasia-Latest a.FJ-Phoenix-Anastasia-EpCard')
        : doc.select('a.FJ-Phoenix-Anastasia-EpCard');
    for (var el in scope) {
      final href = el.attr('href') ?? '';
      if (href.isEmpty || seen.contains(href)) continue;
      seen.add(href);
      final img = el.selectFirst('img.FJ-Phoenix-Anastasia-EpCard-Img');
      final title =
          el.selectFirst('.FJ-Phoenix-Anastasia-EpCard-Name')?.text ??
              img?.attr('alt') ??
              '';
      if (title.isEmpty) continue;
      MManga anime = MManga();
      anime.name = title.trim();
      anime.link = abs(href);
      anime.imageUrl = img?.attr('src') ?? '';
      list.add(anime);
    }
    return list;
  }

  @override
  Future<MPages> getPopular(int page) async {
    final res = (await client.get(Uri.parse(baseUrl))).body;
    final doc = parseHtml(res);
    return MPages(parseCards(doc), false);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res = (await client.get(Uri.parse(baseUrl))).body;
    final doc = parseHtml(res);
    return MPages(parseCards(doc, latestOnly: true), false);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final searchUrl =
        '$baseUrl/search/?q=${Uri.encodeQueryComponent(query)}';
    String? ajaxUrl;
    String? nonce;
    try {
      final inline = (await client.get(Uri.parse(searchUrl))).body;
      for (var script in parseHtml(inline).select('script')) {
        final data = script.text ?? '';
        if (data.contains('fjSearchPageData')) {
          final start = data.indexOf('{');
          final end = data.lastIndexOf('}');
          if (start >= 0 && end > start) {
            final config =
                jsonDecode(data.substring(start, end + 1)) as Map;
            ajaxUrl = config['ajax_url']?.toString();
            nonce = config['nonce']?.toString();
          }
          break;
        }
      }
    } catch (_) {}
    if (nonce == null) return MPages([], false);

    try {
      final body =
          (await client.post(
            Uri.parse(ajaxUrl ?? '$baseUrl/wp-admin/admin-ajax.php'),
            headers: {'Referer': searchUrl},
            body: {
              'action': 'phoenix_search',
              'nonce': nonce,
              'q': query,
              'type': 'all',
              'genre': '',
              'status': '',
              'year': '',
              'season': '',
              'sort': 'relevance',
              'page': '1',
              'per_page': '25',
              'dropdown': '0',
            },
          )).body;
      final response = jsonDecode(body) as Map;
      final results =
          ((response['data'] as Map?)?['results'] as List?) ?? [];
      List<MManga> list = [];
      for (var item in results) {
        final url = item['url']?.toString() ?? '';
        final title = item['title_ar']?.toString() ?? '';
        if (url.isEmpty || title.isEmpty) continue;
        MManga anime = MManga();
        anime.name = title;
        anime.link = url;
        anime.imageUrl = item['thumbnail_url']?.toString() ?? '';
        list.add(anime);
      }
      return MPages(list, false);
    } catch (_) {
      return MPages([], false);
    }
  }

  @override
  Future<MManga> getDetail(String url) async {
    var fixed = abs(url);
    if (fixed.contains('/episodes/')) {
      var slug = substringAfter(fixed, '/episodes/').replaceAll(RegExp(r'/$'), '');
      slug = slug.replaceAll(RegExp(r'-episode-\d+$'), '');
      fixed = '$baseUrl/animes/$slug';
    }
    final doc = parseHtml((await client.get(Uri.parse(fixed))).body);
    MManga anime = MManga();

    String? ldName;
    String? ldDesc;
    String? ldImg;
    for (var sc in doc.select('script[type="application/ld+json"]')) {
      try {
        final j = jsonDecode(sc.text ?? '');
        if (j is Map && j['name'] != null) {
          ldName = j['name']?.toString();
          ldDesc = j['description']?.toString();
          final img = j['image'];
          ldImg = img is String ? img : img?['url']?.toString();
          break;
        }
      } catch (_) {}
    }

    var title = (ldName ?? doc.selectFirst('h1')?.text ?? '')
        .replaceAll(RegExp(r'\s*\|\s*أنمي فينيكس.*$'), '')
        .replaceAll(RegExp(r'^أنمي\s+'), '')
        .replaceAll('مترجم', '')
        .trim();
    anime.name = title;
    anime.imageUrl = ldImg ??
        doc.selectFirst('meta[property="og:image"]')?.attr('content') ??
        '';
    anime.description =
        ldDesc ?? doc.selectFirst('meta[property="og:description"]')?.attr('content') ?? '';

    if (fixed.contains('/movies/')) {
      final watch =
          '${fixed.replaceAll(RegExp(r'/$'), '')}/watch';
      MChapter ep = MChapter();
      ep.name = 'الفيلم';
      ep.url = watch;
      anime.chapters = [ep];
      return anime;
    }

    List<MChapter> eps = [];
    final seen = <String>{};
    for (var el in doc.select('a.FJ-EpPill')) {
      final href = el.attr('href') ?? '';
      if (!href.contains('/episodes/') || seen.contains(href)) continue;
      seen.add(href);
      final numM = RegExp(r'(\d+)\s*$').firstMatch(el.text ?? '') ??
          RegExp(r'-episode-(\d+)').firstMatch(href);
      MChapter ep = MChapter();
      ep.name = 'الحلقة ${numM?.group(1) ?? ''}';
      ep.url = abs(href);
      eps.add(ep);
    }
    eps.sort((a, b) {
      final numA = RegExp(r'(\d+)').firstMatch(a.url ?? '')?.group(1);
      final numB = RegExp(r'(\d+)').firstMatch(b.url ?? '')?.group(1);
      return (int.tryParse(numA ?? '') ?? 0) - (int.tryParse(numB ?? '') ?? 0);
    });
    anime.chapters = eps;
    return anime;
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    _seen = [];
    final doc = parseHtml((await client.get(Uri.parse(url))).body);
    final template = doc.selectFirst('#player-html-template');
    if (template == null) return [];

    List<MVideo> videos = [];
    final videoSrc = template.selectFirst('video source')?.attr('src')?.trim() ?? '';
    if (videoSrc.isNotEmpty) {
      final qMatch = RegExp(r'(\d{3,4})p').firstMatch(videoSrc);
      final quality = qMatch?.group(1) ?? '';
      videos.add(MVideo(
        videoSrc,
        quality.isEmpty ? 'Default' : '${quality}p',
        videoSrc,
        headers: {'Referer': baseUrl},
      ));
    } else {
      for (var iframe in template.select('iframe')) {
        final iframeUrl = iframe.attr('src') ?? '';
        if (iframeUrl.isEmpty) continue;
        videos.addAll(await getSourceVideos(iframeUrl, url));
      }
    }
    return sortVideos(videos);
  }

  Future<List<MVideo>> getSourceVideos(String srcUrl, String referer) async {
    if (_seen == null) _seen = [];
    if (srcUrl.isEmpty || srcUrl == referer || _seen.contains(srcUrl)) return [];
    _seen.add(srcUrl);
    final lower = srcUrl.toLowerCase();
    try {
      if (lower.contains('dood')) return await doodExtractor(srcUrl, null);
      if (lower.contains('voe')) return await voeExtractor(srcUrl, null);
      if (lower.contains('mp4upload')) {
        return await mp4UploadExtractor(srcUrl, null, '', '');
      }
      if (lower.contains('ok.ru')) return await okruExtractor(srcUrl);
      if (lower.contains('vidbom') ||
          lower.contains('vidbam') ||
          lower.contains('vidbm')) {
        return await vidBomExtractor(srcUrl);
      }
      if (lower.contains('streamtape')) {
        return await streamTapeExtractor(srcUrl, null);
      }
      if (lower.contains('filemoon')) {
        return await filemoonExtractor(srcUrl, '', '');
      }
      if (lower.contains('streamwish')) {
        return await streamWishExtractor(srcUrl, '');
      }
    } catch (_) {}
    if (RegExp(r'\.(m3u8|mp4)($|\?)').hasMatch(lower)) {
      return [MVideo(srcUrl, 'Default', srcUrl, headers: {'Referer': referer})];
    }
    try {
      final pageText =
          (await client.get(Uri.parse(srcUrl), headers: {'Referer': referer}))
              .body;
      final direct = RegExp(
        r'(https?://[^"'<>\s]+?\.(?:m3u8|mp4)(?:\?[^"'<>\s]*)?)',
      ).firstMatch(pageText)?.group(1);
      if (direct != null) {
        return [MVideo(direct, 'Default', direct, headers: {'Referer': srcUrl})];
      }
    } catch (_) {}
    return [];
  }

  List<MVideo> sortVideos(List<MVideo> videos) {
    videos.sort((a, b) {
      final numA =
          int.tryParse(
                RegExp(r'(\d{3,4})\s*p').firstMatch(a.quality)?.group(1) ??
                    '',
              ) ??
              0;
      final numB =
          int.tryParse(
                RegExp(r'(\d{3,4})\s*p').firstMatch(b.quality)?.group(1) ??
                    '',
              ) ??
              0;
      return numB - numA;
    });
    return videos;
  }
}

AnimePhoenix main(MSource source) {
  return AnimePhoenix(source: source);
}