import 'package:mangayomi/bridge_lib.dart';
import 'dart:convert';

class Animerco extends MProvider {
  Animerco({required this.source});

  MSource source;

  final Client client = Client();

  List<String>? _seen;

  String get baseUrl => source.baseUrl ?? '';

  @override
  Future<MPages> getPopular(int page) async {
    final url = page <= 1 ? '$baseUrl/animes/' : '$baseUrl/animes/page/$page/';
    final res = (await client.get(Uri.parse(url))).body;
    return parseMediaBlock(res);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url = page <= 1
        ? '$baseUrl/episodes/'
        : '$baseUrl/episodes/page/$page/';
    final res = (await client.get(Uri.parse(url))).body;
    return parseMediaBlock(res);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final res =
        (await client.get(Uri.parse('$baseUrl/?s=${Uri.encodeQueryComponent(query)}')))
            .body;
    return parseMediaBlock(res);
  }

  MPages parseMediaBlock(String res) {
    final doc = parseHtml(res);
    List<MManga> list = [];
    final seen = <String>{};
    for (var card in doc.select('.media-block')) {
      final m = cardToManga(card);
      if (m != null && m.link.isNotEmpty && seen.add(m.link)) list.add(m);
    }
    final next = doc.select('link[rel="next"], a[rel="next"]');
    return MPages(list, next.isNotEmpty);
  }

  MManga? cardToManga(MElement card) {
    final linkEl = card.selectFirst(
      'a[href*="/animes/"], a[href*="/seasons/"], a[href*="/movies/"], a[href*="/episodes/"]',
    );
    final href = linkEl?.attr('href') ?? '';
    if (!href.startsWith('http')) return null;
    final title =
        (card.selectFirst('.info h3')?.text ?? '').trim().isNotEmpty
            ? card.selectFirst('.info h3')!.text.trim()
            : (card.selectFirst('a.image[title]')?.attr('title') ?? '').trim();
    if (title.isEmpty) return null;
    final img = card.selectFirst('[data-src]');
    MManga anime = MManga();
    anime.name = title;
    anime.link = href;
    anime.imageUrl = img?.attr('data-src') ??
        img?.attr('src') ??
        card.selectFirst('img[src]')?.attr('src') ??
        '';
    return anime;
  }

  int? extractEpNumber(String text) {
    try {
      final decoded = Uri.decodeComponent(text);
      final m = RegExp(r'الحلقة\s*(\d+)').firstMatch(decoded);
      return m != null ? int.tryParse(m.group(1)!) : null;
    } catch (_) {
      return null;
    }
  }

  List<MChapter> collectEpisodes(MDocument doc) {
    List<MChapter> eps = [];
    final seen = <String>{};
    for (var li in doc.select('.episodes-lists li[data-number]')) {
      final href = li.selectFirst('a[href*="/episodes/"]')?.attr('href') ?? '';
      if (href.isEmpty || seen.contains(href)) continue;
      seen.add(href);
      final num =
          int.tryParse(li.attr('data-number') ?? '') ?? extractEpNumber(href);
      if (num == null) continue;
      final name = li.selectFirst('a[title]')?.attr('title') ??
          li.selectFirst('.title h3')?.text ??
          '';
      MChapter ep = MChapter();
      ep.name = name.isEmpty ? 'الحلقة $num' : name.trim();
      ep.url = href;
      eps.add(ep);
    }
    return eps;
  }

  @override
  Future<MManga> getDetail(String url) async {
    if (url.contains('/episodes/')) {
      final doc = parseHtml((await client.get(Uri.parse(url))).body);
      final parent =
          doc.selectFirst('.page-controls a[href*="/animes/"]')?.attr('href') ??
              doc.selectFirst('.breadcrumb a[href*="/animes/"]')?.attr('href') ??
              '';
      if (parent.isNotEmpty) return loadDetails(parent);
      final title = doc.selectFirst('h1')?.text ?? 'Unknown';
      final num = extractEpNumber(url) ?? 1;
      MManga anime = MManga();
      anime.name = title.trim();
      anime.link = url;
      MChapter ep = MChapter();
      ep.name = 'الحلقة $num';
      ep.url = url;
      anime.chapters = [ep];
      return anime;
    }
    return loadDetails(url);
  }

  Future<MManga> loadDetails(String url) async {
    final doc = parseHtml((await client.get(Uri.parse(url))).body);
    MManga anime = MManga();
    anime.name =
        (doc.selectFirst('.media-title h1')?.text ?? doc.selectFirst('h1')?.text ?? '')
            .trim();
    anime.imageUrl =
        doc.selectFirst('.widget-sidebar [data-src]')?.attr('data-src') ??
            doc.selectFirst('meta[property="og:image"]')?.attr('content') ??
            '';
    anime.description =
        doc.selectFirst('.media-story .content p')?.text?.trim() ??
            doc.selectFirst('meta[property="og:description"]')?.attr('content') ??
            '';

    final seasons =
        doc.select('.media-seasons a[href*="/seasons/"]').map((e) {
              return e.attr('href') ?? '';
            }).where((h) => h.isNotEmpty).toSet();

    List<MChapter> eps = [];
    if (seasons.isEmpty) {
      eps = collectEpisodes(doc);
    } else {
      for (var season in seasons) {
        try {
          final seasonDoc =
              parseHtml((await client.get(Uri.parse(season))).body);
          eps.addAll(collectEpisodes(seasonDoc));
        } catch (_) {}
      }
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
  Future<List<MVideo>> getVideoList(String url) async {
    _seen = [];
    final res = (await client.get(Uri.parse(url))).body;
    final doc = parseHtml(res);
    final options = doc.select('.server-list .option');
    if (options.isEmpty) return [];

    String? ajaxUrl;
    String? security;
    final configMatch = RegExp(r'dtAjax\s*=\s*(\{.*?\})').firstMatch(res);
    if (configMatch != null) {
      try {
        final config = jsonDecode(configMatch.group(1)!) as Map;
        ajaxUrl = config['url']?.toString();
        security = config['security']?.toString();
      } catch (_) {}
    }
    final resolvedAjax = (ajaxUrl ?? '').startsWith('http')
        ? (ajaxUrl ?? '')
        : '${baseUrl.replaceAll(RegExp(r'/$'), '')}${(ajaxUrl ?? '').isEmpty ? '/wp-admin/admin-ajax.php' : ajaxUrl!}';

    List<MVideo> videos = [];
    for (var option in options) {
      final post = option.attr('data-post') ?? '';
      final nume = option.attr('data-nume') ?? '';
      final type = (option.attr('data-type') ?? '').isEmpty
          ? 'tv'
          : option.attr('data-type')!;
      final nonce = (option.attr('data-nonce') ?? '').isNotEmpty
          ? option.attr('data-nonce')!
          : (security ?? '');
      if (post.isEmpty || nume.isEmpty || nonce.isEmpty) continue;
      try {
        final body =
            (await client.post(
              Uri.parse(resolvedAjax),
              headers: {'Referer': url, 'X-Requested-With': 'XMLHttpRequest'},
              body: {
                'action': 'player_ajax',
                'security': nonce,
                'post': post,
                'nume': nume,
                'type': type,
              },
            )).body;
        final player = jsonDecode(body) as Map;
        final embed = player['embed_url']?.toString() ?? '';
        if (embed.isEmpty) continue;
        if (player['type'] == 'dtshcode') {
          final frag = parseHtml(embed);
          for (var t in frag.select(
            'iframe[src], iframe[data-src], source[src], video[src]',
          )) {
            videos.addAll(
              await getSourceVideos(t.attr('src') ?? t.attr('data-src') ?? '', url),
            );
          }
          for (var m in RegExp(
            r'(https?://[^"'<>\s]+?\.(?:m3u8|mp4)[^"'<>\s]*)',
          ).allMatches(embed)) {
            videos.addAll(await getSourceVideos(m.group(1)!, url));
          }
        } else {
          var finalEmbed = embed;
          if (embed.startsWith(baseUrl) && embed.contains('/jwplayer/')) {
            try {
              final playerDoc =
                  parseHtml((await client.get(Uri.parse(embed), headers: {'Referer': url})).body);
              final iframe = playerDoc.selectFirst('iframe[src]')?.attr('src') ??
                  playerDoc.selectFirst('iframe[data-src]')?.attr('data-src') ??
                  '';
              if (iframe.startsWith('http')) finalEmbed = iframe;
            } catch (_) {}
          }
          videos.addAll(await getSourceVideos(finalEmbed, url));
        }
      } catch (_) {}
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

Animerco main(MSource source) {
  return Animerco(source: source);
}