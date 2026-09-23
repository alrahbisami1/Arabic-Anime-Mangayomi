import 'package:mangayomi/bridge_lib.dart';
import 'dart:convert';

class Anime3rb extends MProvider {
  Anime3rb({required this.source});

  MSource source;

  final Client client = Client();

  static const titlesSitemap =
      'https://anime3rb.com/storage/sitemaps/titles_sitemap.xml';
  List<List<String>>? cachedTitles;

  String get baseUrl => source.baseUrl ?? '';

  String abs(String url) => url.startsWith('http')
      ? url
      : '${baseUrl}${url.startsWith('/') ? '' : '/'}$url';

  @override
  Future<MPages> getPopular(int page) async {
    final res = (await client.get(Uri.parse(baseUrl))).body;
    final doc = parseHtml(res);
    List<MManga> list = [];
    final seen = <String>{};
    for (var el in doc.select('a.video-card')) {
      final url = el.attr('href') ?? '';
      if (!url.contains('/episode/') || seen.contains(url)) continue;
      seen.add(url);
      final title = el.selectFirst('h3.title-name')?.text ?? '';
      if (title.isEmpty) continue;
      final img = el.selectFirst('img');
      MManga anime = MManga();
      anime.name = title;
      anime.imageUrl = img?.getSrc ?? img?.attr('data-src') ?? '';
      anime.link = abs(url);
      list.add(anime);
    }
    return MPages(list, false);
  }

  @override
  Future<MPages> getLatestUpdates(int page) => getPopular(page);

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    if (cachedTitles == null) {
      cachedTitles = [];
      final res = (await client.get(Uri.parse(titlesSitemap))).body;
      final locs = xpath(res, '//url/loc/text()') ?? [];
      for (var loc in locs) {
        final slug =
            substringAfterLast(loc, '/titles/').replaceAll(RegExp(r'/$'), '');
        if (slug.isEmpty || slug.contains(' ')) continue;
        cachedTitles?.add([slug, slug.replaceAll('-', ' ')]);
      }
    }
    final q = query.trim().toLowerCase();
    List<MManga> list = [];
    for (var t in cachedTitles!) {
      if (list.length >= 30) break;
      if (t[0].toLowerCase().contains(q) || t[1].toLowerCase().contains(q)) {
        MManga anime = MManga();
        anime.name = t[1];
        anime.link = abs('/titles/${t[0]}');
        list.add(anime);
      }
    }
    return MPages(list, false);
  }

  @override
  Future<MManga> getDetail(String url) async {
    var titleUrl = url;
    if (titleUrl.contains('/episode/')) {
      final slug =
          substringBefore(substringAfter(titleUrl, '/episode/'), '/');
      titleUrl = '/titles/$slug';
    }
    final res = (await client.get(Uri.parse(abs(titleUrl)))).body;
    final doc = parseHtml(res);
    MManga anime = MManga();
    var title = doc.selectFirst('meta[property="og:title"]')?.attr('content') ??
        doc.selectFirst('h1')?.text ??
        '';
    title = title
        .replaceAll(' - Anime3rb أنمي عرب', '')
        .replaceAll('أنمي ', '')
        .replaceAll('مترجم', '')
        .trim();
    anime.name = title;
    anime.imageUrl =
        doc.selectFirst('meta[property="og:image"]')?.attr('content') ??
            doc.selectFirst('img[src*="images.anime3rb.com"]')?.attr('src') ??
            '';
    anime.description =
        doc.selectFirst('meta[property="og:description"]')?.attr('content') ??
            '';

    List<MChapter> eps = [];
    final seen = <String>{};
    for (var el in doc.select('a[href*="/episode/"]')) {
      final href = el.attr('href') ?? '';
      if (!href.contains('/episode/') || seen.contains(href)) continue;
      seen.add(href);
      final tag = substringAfter(href, '/episode/');
      var numTxt = RegExp(r'الحلقة\s*\d+').stringMatch(el.text ?? '');
      if (numTxt == null) numTxt = RegExp(r'/\d+(?:/|$)').stringMatch(tag);
      final num = numTxt == null
          ? substringAfterLast(href, '/')
          : numTxt.replaceAll(RegExp(r'\D+'), '');
      MChapter ep = MChapter();
      ep.name = 'الحلقة $num';
      ep.url = abs(href);
      eps.add(ep);
    }
    if (eps.isEmpty) {
      for (var sc in doc.select('script[type="application/ld+json"]')) {
        try {
          final j = jsonDecode(sc.text ?? '');
          if (j is Map) {
            final epList = j['episode'];
            if (epList is List) {
              for (var e in epList) {
                final u = e['url']?.toString() ?? '';
                if (u.isEmpty || !u.contains('/episode/')) continue;
                final nm = e['name']?.toString() ?? '';
                final epTag = RegExp(r'الحلقة \d+').stringMatch(nm);
                MChapter ep = MChapter();
                ep.name = epTag != null
                    ? 'الحلقة ${epTag.replaceAll(RegExp(r'\D+'), '')}'
                    : nm;
                ep.url = abs(u);
                eps.add(ep);
              }
              break;
            }
          }
        } catch (_) {}
      }
    }
    int epNumOf(MChapter c) =>
        int.tryParse(substringAfterLast(c.name ?? '', ' ')) ?? 2147483647;
    eps.sort((a, b) => epNumOf(a).compareTo(epNumOf(b)));
    anime.chapters = eps;
    return anime;
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final episodeHtml =
        (await client.get(Uri.parse(abs(url)), headers: {'Referer': baseUrl}))
            .body;
    String? rawVideoUrl;
    final escaped = RegExp(
      r'&quot;video_url&quot;:&quot;.*?&quot;',
    ).stringMatch(episodeHtml);
    if (escaped != null) {
      rawVideoUrl = escaped
          .replaceAll('&quot;video_url&quot;:&quot;', '')
          .replaceAll('&quot;', '');
    } else {
      final plain = RegExp(r'"video_url"\s*:\s*"[^"]*"').stringMatch(
        episodeHtml,
      );
      if (plain != null) {
        rawVideoUrl = plain
            .replaceAll(RegExp(r'^"video_url"\s*:\s*'), '')
            .replaceAll('"', '');
      }
    }
    if (rawVideoUrl == null) return [];
    final playerUrl = rawVideoUrl
        .replaceAll('\\/', '/')
        .replaceAll('&amp;', '&');

    final playerText =
        (await client.get(Uri.parse(playerUrl), headers: {'Referer': abs(url)}))
            .body;

    String? json;
    var rest = playerText;
    for (var i = 0; i < 12; i++) {
      final m = RegExp(r'video_sources\s*=\s*\[[\s\S]*?\];').stringMatch(rest);
      if (m == null) break;
      final candidate = m
          .replaceAll(RegExp(r'^video_sources\s*=\s*'), '')
          .replaceAll(RegExp(r';$'), '');
      if (candidate.length > 2) json = candidate;
      rest = substringAfter(rest, m);
    }
    if (json == null) return [];

    final sources = jsonDecode(json) as List;
    List<MVideo> videos = [];
    for (var s in sources) {
      final src = s['src']?.toString() ?? '';
      if (s['premium'] == true || src.isEmpty) continue;
      final label = s['label']?.toString() ?? '';
      final res = s['res']?.toString() ?? '';
      final quality = label.isNotEmpty
          ? label
          : res.isNotEmpty
              ? '${res}p'
              : 'Default';
      videos.add(MVideo(src, quality, src, headers: {'Referer': baseUrl}));
    }
    return sortVideos(videos);
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

Anime3rb main(MSource source) {
  return Anime3rb(source: source);
}