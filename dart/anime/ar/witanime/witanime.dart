import 'package:mangayomi/bridge_lib.dart';

class WitAnime extends MProvider {
  WitAnime({required this.source});

  MSource source;

  final Client client = Client();

  List<String>? _seen;

  static const Map<String, String> browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36',
    'Accept-Language': 'ar,en;q=0.8',
  };

  String get baseUrl => source.baseUrl ?? '';

  String abs(String url) => url.startsWith('http')
      ? url
      : '${baseUrl}${url.startsWith('/') ? '' : '/'}$url';

  String bgUrl(String style) {
    final m = RegExp(r"url\('([^']+)'\)").stringMatch(style);
    if (m != null) {
      return m.substring(5, m.length - 2);
    }
    final m2 = RegExp(r'url\("([^"]+)"\)').stringMatch(style);
    if (m2 != null) {
      return m2.substring(5, m2.length - 2);
    }
    return '';
  }

  int? extractEpNumber(String text) {
    try {
      final decoded = Uri.decodeComponent(text);
      final m = RegExp(r'الحلقة\s*\d+').stringMatch(decoded);
      if (m == null) return null;
      return int.tryParse(substringAfter(m, 'الحلقة').trim());
    } catch (_) {
      return null;
    }
  }

  MPages parseCards(String res) {
    final doc = parseHtml(res);
    List<MManga> list = [];
    final seen = <String>{};
    final cards = doc.select('div.anime-card, div.episode-card');
    for (var card in cards) {
      final m = cardToManga(card);
      if (m != null && m.link.isNotEmpty && seen.add(m.link)) list.add(m);
    }
    return MPages(list, false);
  }

  MManga? cardToManga(MElement card) {
    final linkEl = card.selectFirst('a[href*="/anime/"]');
    final href = linkEl?.attr('href') ?? '';
    if (href.isEmpty || href.contains('/anime-status/')) return null;
    final info = card.selectFirst('.info') ?? card;
    final h4 = info.selectFirst('h4 a');
    final h3 = info.selectFirst('h3');
    final title =
        ((h4?.text ?? '').trim().isNotEmpty ? h4!.text.trim() : (h3?.text ?? '').trim())
            .isNotEmpty
            ? ((h4?.text ?? '').trim().isNotEmpty ? h4!.text.trim() : (h3?.text ?? '').trim())
            : (linkEl?.attr('title') ?? '').trim();
    if (title.isEmpty) return null;
    final img = card.selectFirst('.image');
    MManga anime = MManga();
    anime.name = title;
    anime.link = abs(href);
    anime.imageUrl = img == null
        ? (card.selectFirst('img')?.attr('src') ?? '')
        : bgUrl(img.attr('style') ?? '');
    return anime;
  }

  @override
  Future<MPages> getPopular(int page) async {
    final url = page <= 1 ? '$baseUrl/anime/' : '$baseUrl/anime/page/$page/';
    final res = (await client.get(Uri.parse(url), headers: browserHeaders)).body;
    return parseCards(res);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url = page <= 1 ? baseUrl : '$baseUrl/anime/page/$page/';
    final res = (await client.get(Uri.parse(url), headers: browserHeaders)).body;
    return parseCards(res);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final res =
        (await client
                .get(
                  Uri.parse('$baseUrl/?s=${Uri.encodeQueryComponent(query)}'),
                  headers: browserHeaders,
                ))
            .body;
    return parseCards(res);
  }

  List<MChapter> collectEpisodes(MDocument doc) {
    List<MChapter> eps = [];
    final seen = <String>{};
    for (var a in doc.select('.episodes-lists a.title')) {
      final href = a.attr('href') ?? '';
      if (href.isEmpty || seen.contains(href)) continue;
      seen.add(href);
      final text = a.text ?? '';
      final num = extractEpNumber(text) ?? extractEpNumber(href) ?? 0;
      MChapter ep = MChapter();
      ep.name = num > 0
          ? 'الحلقة $num'
          : text.trim().isEmpty
              ? 'الحلقة ${eps.length + 1}'
              : text.trim();
      ep.url = abs(href);
      eps.add(ep);
    }
    return eps;
  }

  @override
  Future<MManga> getDetail(String url) async {
    final animeUrl = url.replaceAll(RegExp(r'/$'), '');
    MManga anime = MManga();
    List<MChapter> eps = [];
    final seen = <String>{};
    for (var i = 1; i < 60; i++) {
      final pageUrl = i == 1 ? animeUrl : '$animeUrl/page/$i/';
      late String res;
      try {
        res = (await client
                .get(Uri.parse(pageUrl), headers: browserHeaders)
                .timeout(Duration(seconds: 20)))
            .body;
      } catch (_) {
        break;
      }
      final doc = parseHtml(res);
      if (i == 1) {
        anime.name =
            (doc.selectFirst('h1')?.text ?? doc.selectFirst('main h1')?.text ?? '')
                .trim();
        final asideImage = doc.selectFirst('.widget-sidebar .image');
        anime.imageUrl = asideImage == null
            ? (doc.selectFirst('meta[property="og:image"]')?.attr('content') ?? '')
            : bgUrl(asideImage.attr('style') ?? '');
        anime.description =
            doc.selectFirst('.media-story .content p')?.text?.trim() ??
                doc.selectFirst('meta[property="og:description"]')?.attr('content') ??
                '';
        for (var li in doc.select('ul.media-info li')) {
          final label = Uri.decodeComponent(li.text ?? '');
          if (label.contains('نوع')) {
            anime.genre = li
                .select('span')
                .map((e) => e.text ?? '')
                .where((t) => t.trim().isNotEmpty)
                .toList();
            break;
          }
        }
      }
      final pageEps = collectEpisodes(doc);
      int added = 0;
      for (var ep in pageEps) {
        if (seen.add(ep.url)) {
          eps.add(ep);
          added++;
        }
      }
      final hasNext = RegExp('/page/${i + 1}/').hasMatch(res);
      if (added == 0) break;
      if (!hasNext) break;
    }
    eps.sort((a, b) {
      final numA = extractEpNumber(a.name) ?? extractEpNumber(a.url) ?? 0;
      final numB = extractEpNumber(b.name) ?? extractEpNumber(b.url) ?? 0;
      return numA - numB;
    });
    anime.chapters = eps;
    return anime;
  }

  @override
  Future<List<MVideo>> getVideoList(String data) async {
    _seen = [];
    final url = data.trim();
    if (url.isEmpty) return [];
    late String res;
    try {
      res = (await client
              .get(Uri.parse(abs(url)), headers: browserHeaders)
              .timeout(Duration(seconds: 20)))
          .body;
    } catch (_) {
      return [];
    }
    final doc = parseHtml(res);
    final servers = doc.select('.server-list a.episode-server');
    if (servers.isEmpty) {
      List<MVideo> fallbackVideos = [];
      for (var t in doc.select(
        'iframe[src], iframe[data-src], source[src], video[src], #click-player[data-src]',
      )) {
        final href = t.attr('src') ?? t.attr('data-src') ?? '';
        if (href.isEmpty || href == '#') continue;
        final subs = await getSourceVideos(href, abs(url));
        if (subs != null && subs.isNotEmpty) fallbackVideos.addAll(subs);
      }
      return sortVideos(fallbackVideos);
    }
    List<MVideo> videos = [];
    for (var s in servers) {
      final embed = s.attr('data-url') ?? '';
      if (embed.isEmpty) continue;
      final subs = await getSourceVideos(embed, abs(url));
      if (subs != null && subs.isNotEmpty) videos.addAll(subs);
    }
    return sortVideos(videos);
  }

  Future<List<MVideo>> getSourceVideos(String srcUrl, String referer) async {
    if (_seen == null) _seen = [];
    if (srcUrl.isEmpty || srcUrl == referer || _seen.contains(srcUrl)) return [];
    _seen.add(srcUrl);
    final lower = srcUrl.toLowerCase();
    try {
      if (lower.contains('dood')) return (await doodExtractor(srcUrl, null)) ?? [];
      if (lower.contains('voe')) return (await voeExtractor(srcUrl, null)) ?? [];
      if (lower.contains('mp4upload')) {
        return (await mp4UploadExtractor(srcUrl, null, '', '')) ?? [];
      }
      if (lower.contains('ok.ru')) return (await okruExtractor(srcUrl)) ?? [];
      if (lower.contains('vidbom') ||
          lower.contains('vidbam') ||
          lower.contains('vidbm') ||
          lower.contains('vidbem')) {
        return (await vidBomExtractor(srcUrl)) ?? [];
      }
      if (lower.contains('streamtape') || lower.contains('watchsb')) {
        return (await streamTapeExtractor(srcUrl, null)) ?? [];
      }
      if (lower.contains('filemoon')) {
        return (await filemoonExtractor(srcUrl, '', '')) ?? [];
      }
      if (lower.contains('streamwish')) {
        return (await streamWishExtractor(srcUrl, '')) ?? [];
      }
      if (lower.contains('sendvid')) {
        return (await sendVidExtractor(srcUrl, null, '')) ?? [];
      }
      if (lower.contains('yourupload')) {
        return (await yourUploadExtractor(srcUrl, null, null, '')) ?? [];
      }
      if (lower.contains('drive.google.com') ||
          lower.contains('docs.google.com') ||
          lower.contains('drive.usercontent')) {
        return (await googleDriveExtractor(srcUrl, referer)) ?? [];
      }
    } catch (_) {}
    if (lower.contains('drive.google.com') ||
        lower.contains('docs.google.com') ||
        lower.contains('drive.usercontent.google.com')) {
      return (await googleDriveExtractor(srcUrl)) ?? [];
    }
    if (RegExp(r'\.(m3u8|mp4)($|\?)').hasMatch(lower)) {
      return [MVideo(srcUrl, 'Default', srcUrl, headers: {'Referer': referer})];
    }
    try {
      final pageText =
          (await client
                  .get(Uri.parse(srcUrl), headers: {'Referer': referer})
                  .timeout(Duration(seconds: 12)))
              .body;
      final direct = RegExp(
        r'''https?://[^"'<>\s]+?\.(?:m3u8|mp4)(?:\?[^"'<>\s]*)?''',
      ).stringMatch(pageText);
      if (direct != null) {
        return [MVideo(direct, 'Default', direct, headers: {'Referer': srcUrl})];
      }
    } catch (_) {}
    return [];
  }

  Future<List<MVideo>> googleDriveExtractor(String srcUrl, [String? referer]) async {
    String? fileId;
    final idPart = RegExp(r'''/d/[^/]+''').stringMatch(srcUrl);
    if (idPart != null) {
      fileId = substringAfter(idPart, '/d/');
    } else {
      final q = Uri.tryParse(srcUrl)?.queryParameters;
      fileId = q?['id'] ?? q?['docid'];
    }
    if (fileId == null || fileId.isEmpty) return [];
    try {
      final confirmed = (await client
              .get(
                Uri.parse(
                  'https://drive.usercontent.google.com/download?id=$fileId&export=download&confirm=t',
                ),
                headers: {...browserHeaders, 'Referer': 'https://drive.google.com/'},
                followRedirects: false,
              ))
          .statusCode;
      if (confirmed == 302) {
        final redir =
            (await client.get(
                  Uri.parse(
                    'https://drive.usercontent.google.com/download?id=$fileId&export=download&confirm=t',
                  ),
                  headers: {...browserHeaders, 'Referer': 'https://drive.google.com/'},
                ))
                .request
                .url;
        return [
          MVideo(redir.toString(), 'Drive', redir.toString(), headers: {'Referer': 'https://drive.google.com/'}),
        ];
      }
    } catch (_) {}
    return [];
  }

  List<MVideo> sortVideos(List<MVideo> videos) {
    videos.sort((a, b) {
      final qA = RegExp(r'\d{3,4}\s*p').stringMatch(a.quality);
      final numA =
          int.tryParse(substringBefore(qA ?? '', 'p').trim()) ?? 0;
      final qB = RegExp(r'\d{3,4}\s*p').stringMatch(b.quality);
      final numB =
          int.tryParse(substringBefore(qB ?? '', 'p').trim()) ?? 0;
      return numB - numA;
    });
    return videos;
  }
}

WitAnime main(MSource source) {
  return WitAnime(source: source);
}