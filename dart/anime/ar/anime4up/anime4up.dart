import 'package:mangayomi/bridge_lib.dart';
import 'dart:convert';

class Anime4up extends MProvider {
  Anime4up({required this.source});

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

  int? extractEpNumber(String text) {
    try {
      final decoded = Uri.decodeComponent(text);
      final m = RegExp(r'الحلقة\s*(\d+)').firstMatch(decoded);
      return m != null ? int.tryParse(m.group(1)!) : null;
    } catch (_) {
      return null;
    }
  }

  String qualityFrom(String q) {
    final u = q.trim().toUpperCase();
    if (u.contains('FHD')) return '1080p';
    if (u.contains('HD')) return '720p';
    if (u.contains('SD')) return '480p';
    return q.trim().isEmpty ? 'Default' : q.trim();
  }

  MPages parseCards(String res) {
    final doc = parseHtml(res);
    List<MManga> list = [];
    final seen = <String>{};
    for (var el in doc.select('div.anime-card-themex')) {
      final m = cardToManga(el);
      if (m != null && m.link.isNotEmpty && seen.add(m.link)) list.add(m);
    }
    return MPages(list, false);
  }

  MManga? cardToManga(MElement card) {
    final linkEl =
        card.selectFirst('.anime-card-title h3 a') ?? card.selectFirst('a.overlay');
    final href = linkEl?.attr('href') ?? '';
    if (href.isEmpty || href.contains('/episode/')) return null;
    final titleEl = card.selectFirst('.anime-card-title');
    final title =
        (titleEl?.attr('title') ?? '').trim().isNotEmpty
            ? (titleEl!.attr('title') ?? '').trim()
            : (linkEl?.attr('title') ?? '').trim();
    final fallbackTitle = card.selectFirst('img')?.attr('alt') ?? '';
    final finalTitle = title.isNotEmpty ? title : fallbackTitle.trim();
    if (finalTitle.isEmpty) return null;
    final img = card.selectFirst('.anime-card-poster .hover img');
    MManga anime = MManga();
    anime.name = finalTitle;
    anime.link = abs(href);
    anime.imageUrl =
        img?.attr('data-image') ?? img?.attr('data-src') ?? img?.attr('src') ?? '';
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
    final rows = doc.select('#episodesList a[href*="/episode/"]');
    for (var a in rows) {
      final href = a.attr('href') ?? '';
      if (href.isEmpty || seen.contains(href)) continue;
      seen.add(href);
      final num = extractEpNumber(href) ?? extractEpNumber(a.text ?? '') ?? 0;
      MChapter ep = MChapter();
      ep.name = num > 0
          ? 'الحلقة $num'
          : (a.text ?? '').trim().isEmpty
              ? 'الحلقة ${eps.length + 1}'
              : (a.text ?? '').trim();
      ep.url = abs(href);
      eps.add(ep);
    }
    if (eps.isNotEmpty) return eps;
    for (var a in doc.select('ul.all-episodes-list li a')) {
      final href = a.attr('href') ?? '';
      if (href.isEmpty || !href.contains('/episode/') || seen.contains(href)) continue;
      seen.add(href);
      final num = extractEpNumber(href) ?? extractEpNumber(a.text ?? '') ?? 0;
      MChapter ep = MChapter();
      ep.name = num > 0
          ? 'الحلقة $num'
          : (a.text ?? '').trim().isEmpty
              ? 'الحلقة ${eps.length + 1}'
              : (a.text ?? '').trim();
      ep.url = abs(href);
      eps.add(ep);
    }
    return eps;
  }

  @override
  Future<MManga> getDetail(String url) async {
    final animeUrl = abs(url).replaceAll(RegExp(r'/$'), '');
    MManga anime = MManga();
    List<MChapter> eps = [];
    final seen = <String>{};
    for (var i = 1; i < 40; i++) {
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
            (doc.selectFirst('h1.anime-details-title')?.text ??
                    doc.selectFirst('h1')?.text ??
                    '')
                .trim();
        final thumb = doc.selectFirst('.anime-thumbnail img');
        anime.imageUrl =
            thumb?.attr('data-image') ??
                thumb?.attr('data-src') ??
                thumb?.attr('src') ??
                '';
        anime.description =
            doc.selectFirst('p.anime-story')?.text?.trim() ??
                doc.selectFirst('meta[property="og:description"]')?.attr('content') ??
                '';
        anime.genre =
            doc
                .select('ul.anime-genres li a')
                .map((e) => e.text ?? '')
                .where((t) => t.trim().isNotEmpty)
                .toList();
      }
      int added = 0;
      for (var ep in collectEpisodes(doc)) {
        if (seen.add(ep.url)) {
          eps.add(ep);
          added++;
        }
      }
      if (added == 0) break;
      if (!RegExp('/page/${i + 1}/').hasMatch(res)) break;
    }
    eps.sort((a, b) {
      final numA = extractEpNumber(a.name) ?? extractEpNumber(a.url) ?? 0;
      final numB = extractEpNumber(b.name) ?? extractEpNumber(b.url) ?? 0;
      return numA - numB;
    });
    anime.chapters = eps;
    return anime;
  }

  List<MVideo> inertiaStreams(String body, String referer) {
    try {
      final root = jsonDecode(body);
      final out = <MVideo>[];
      final keys = <String>{};
      void walk(Object? node, String? quality) {
        if (node is Map) {
          final q =
              (node['quality'] ?? node['label'] ?? node['name'] ?? quality)
                  .toString()
                  .trim();
          final eff = q.isEmpty || q == 'null' ? 'Default' : q;
          for (final k in ['link', 'url', 'src', 'file']) {
            final v = node[k];
            if (v is String &&
                v.startsWith('http') &&
                RegExp(r'\.(m3u8|mp4)($|\?)').hasMatch(v) &&
                keys.add(v)) {
              out.add(MVideo(v, eff, v, headers: {'Referer': referer}));
            }
          }
          for (final child in node.values) {
            if (child is Map || child is List) walk(child, eff == 'Default' ? null : eff);
          }
        } else if (node is List) {
          for (final e in node) {
            walk(e, quality);
          }
        }
      }

      walk(root, null);
      return out;
    } catch (_) {
      return [];
    }
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
    final servers = doc.select('#episode-servers li[data-watch]');
    if (servers.isEmpty) return [];
    List<MVideo> videos = [];
    for (var s in servers) {
      final embed = s.attr('data-watch') ?? '';
      if (embed.isEmpty) continue;
      final quality = qualityFrom(s.selectFirst('span.quality')?.text ?? '');
      final subs = await getSourceVideos(embed, abs(url), quality);
      if (subs != null && subs.isNotEmpty) videos.addAll(subs);
    }
    return sortVideos(videos);
  }

  Future<List<MVideo>> getSourceVideos(
    String srcUrl,
    String referer,
    String quality,
  ) async {
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
      return [MVideo(srcUrl, quality, srcUrl, headers: {'Referer': referer})];
    }
    try {
      final checkText =
          (await client
                  .get(Uri.parse(srcUrl), headers: {'Referer': referer})
                  .timeout(Duration(seconds: 12)))
              .body;
      final inertia = lower.contains('share4max') || lower.contains('megamax')
          ? inertiaStreams(checkText, srcUrl)
          : <MVideo>[];
      if (inertia.isNotEmpty) return inertia;
      final direct = RegExp(
        r'''(https?://[^"'<>\s]+?\.(?:m3u8|mp4)(?:\?[^"'<>\s]*)?)''',
      ).firstMatch(checkText)?.group(1);
      if (direct != null) {
        return [MVideo(direct, quality, direct, headers: {'Referer': srcUrl})];
      }
    } catch (_) {}
    return [];
  }

  Future<List<MVideo>> googleDriveExtractor(String srcUrl, [String? referer]) async {
    String? fileId;
    final idMatch = RegExp(r'''(/d/([^/]+))''').firstMatch(srcUrl);
    if (idMatch != null) {
      fileId = idMatch.group(2);
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

Anime4up main(MSource source) {
  return Anime4up(source: source);
}