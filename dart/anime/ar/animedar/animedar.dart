import 'package:mangayomi/bridge_lib.dart';
import 'dart:convert';

class Animedar extends MProvider {
  Animedar({required this.source});

  MSource source;

  final Client client = Client();

  List<String>? _seen;

  String get baseUrl => source.baseUrl ?? '';

  String abs(String url) => url.startsWith('http')
      ? url
      : '${baseUrl}${url.startsWith('/') ? '' : '/'}$url';

  MManga? cardToManga(MElement cardEl) {
    final link = cardEl.selectFirst('.bsx a[href*="/anime-p/"]') ??
        cardEl.selectFirst('a[href*="/anime-p/"]');
    final href = link?.attr('href') ?? '';
    if (href.isEmpty) return null;
    final title =
        (link?.attr('title') ?? '').trim().isNotEmpty
            ? link!.attr('title')!.trim()
            : (cardEl.selectFirst('.tt h2')?.text ?? '').trim();
    if (title.isEmpty) return null;
    final img = cardEl.selectFirst('img');
    MManga anime = MManga();
    anime.name = title;
    anime.link = abs(href);
    anime.imageUrl =
        img?.attr('src') ?? img?.attr('data-src') ?? img?.attr('data-lazy-src') ?? '';
    return anime;
  }

  MPages parseCards(String res) {
    final doc = parseHtml(res);
    List<MManga> list = [];
    final seen = <String>{};
    for (var el in doc.select('article.bs')) {
      final m = cardToManga(el);
      if (m != null && m.link.isNotEmpty && seen.add(m.link)) list.add(m);
    }
    return MPages(list, false);
  }

  @override
  Future<MPages> getPopular(int page) async {
    final url = page <= 1 ? baseUrl : '$baseUrl/page/$page/';
    final res = (await client.get(Uri.parse(url))).body;
    return parseCards(res);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url = page <= 1 ? baseUrl : '$baseUrl/page/$page/';
    final res = (await client.get(Uri.parse(url))).body;
    return parseCards(res);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final res =
        (await client.get(Uri.parse('$baseUrl?s=${Uri.encodeQueryComponent(query)}')))
            .body;
    return parseCards(res);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final doc = parseHtml((await client.get(Uri.parse(abs(url)))).body);
    MManga anime = MManga();
    anime.name =
        (doc.selectFirst('.infox h1.entry-title')?.text ??
                doc.selectFirst('h1.entry-title')?.text ??
                '')
            .trim();
    final thumb = doc.selectFirst('.thumbook .thumb img') ??
        doc.selectFirst('.thumb img') ??
        doc.selectFirst('img.ts-post-image');
    anime.imageUrl = thumb?.attr('src') ??
        thumb?.attr('data-src') ??
        thumb?.attr('data-lazy-src') ??
        '';
    anime.description = doc.selectFirst('.entry-content[itemprop=description]')?.text?.trim() ??
        doc.selectFirst('div.entry-content')?.text?.trim() ??
        '';
    anime.genre =
        doc.select('.genxed a').map((e) => e.text ?? '').where((t) => t.trim().isNotEmpty).toList();

    final epDivs = doc.select('#EpList1 .CSB').length;
    final serverBlocks = doc.select('#ServerList1 div.divv11').length;

    List<MChapter> eps = [];
    final count = epDivs > 0 ? epDivs : serverBlocks;
    for (var i = 0; i < count; i++) {
      MChapter ep = MChapter();
      ep.name = 'الحلقة ${i + 1}';
      ep.url = '${abs(url)}|$i';
      eps.add(ep);
    }
    anime.chapters = eps;
    return anime;
  }

  String? serverEmbedUrl(String type, String id) {
    final vid = id.trim();
    if (vid.isEmpty) return null;
    switch (type.toLowerCase()) {
      case 'asnwish':
        return 'https://asnwish.com/e/$vid';
      case 'videa':
        return 'https://videa.hu/player?v=$vid';
      case 'mp4upload':
        return 'https://www.mp4upload.com/embed-$vid.html';
      case 'vidbem':
      case 'vidbom':
        return 'https://vidbem.com/embed-$vid.html';
      case 'vidbam':
        return 'https://vidbam.org/embed-$vid.html';
      case 'vedbom':
        return 'https://vedbom.com/embed-$vid.html';
      case 'vidbm':
        return 'https://vidbm.com/embed-$vid.html';
      case 'vidhd':
        return 'https://vidhd.net/embed-$vid.html';
      case 'vidshare':
        return 'https://vidshare.tv/embed-$vid.html';
      case 'vidshar':
        return 'https://vidshar.org/embed-$vid.html';
      case 'segavid':
        return 'https://segavid.com/embed-$vid.html';
      case 'sblanh':
        return 'https://sblanh.com/e/$vid';
      case 'highload':
        return 'https://highload.to/e/$vid';
      case 'upvideo':
        return 'https://upvideo.to/e/$vid';
      case 'upstream':
        return 'https://upstream.to/embed-$vid.html';
      case 'dailymotion':
        return 'https://www.dailymotion.com/embed/video/$vid';
      case 'solidfiles':
        return 'https://www.solidfiles.com/e/$vid';
      case 'vid4up':
        return 'https://cdn2.vid4up.xyz/embedvideo/$vid';
      case 'animemixat':
      case 'animeup':
        return 'https://www.anime4up.net/player/$vid';
      case 'uqload':
        return 'https://uqload.com/embed-$vid.html';
      case 'ninjastream':
        return 'https://ninjastream.to/watch/$vid';
      case 'userload':
        return 'https://userload.co/embed/$vid';
      case 'vedshare':
        return 'https://vedshare.com/embed-$vid.html';
      case 'myviid':
        return 'https://myviid.net/embed-$vid.html';
      case 'govid':
        return 'https://govid.me/embed-$vid.html';
      case 'playtube':
        return 'https://playtube.ws/embed-$vid.html';
      case 'dood':
      case 'doodstream':
        return 'https://dood.so/e/$vid';
      case 'mixdrop':
        return 'https://mixdrop.to/e/$vid';
      case 'ok':
        return 'https://www.ok.ru/videoembed/$vid';
      case 'fembed':
        return 'https://fembed.com/v/$vid';
      case 'holavid':
        return 'https://holavid.com/embed-$vid.html';
      case 'uptobox':
      case 'uptostream':
        return 'https://uptostream.com/iframe/$vid';
      case 'samaup':
        return 'https://samaup.cc/embed-$vid.html';
      case 'watchsb':
        return 'https://watchsb.com/e/$vid';
      case 'soraplay':
        return 'https://soraplay.xyz/embed/$vid';
      case 'vidyard':
        return 'https://play.vidyard.com/$vid';
      case 'youtube':
        return 'https://www.youtube.com/embed/$vid';
      case 'goved':
        return 'https://goved.org/embed-$vid.html';
      case 'sendvid':
        return 'https://sendvid.com/embed/$vid';
      case 'streamhub':
        return 'https://streamhub.to/e/$vid';
      case 'clipwatching':
        return 'https://clipwatching.com/embed-$vid.html';
      case 'vidfast':
        return 'https://vidfast.co/embed-$vid.html';
      case 'mega':
        return 'https://mega.nz/embed/${vid.replaceAll(":/mega.nz/embed#!", "")}';
      case 'yourupload':
        return 'https://www.yourupload.com/embed/$vid';
      case 'temp':
      case 'top4top':
        return vid.startsWith('http') ? vid : null;
      case 'drive':
        return 'https://drive.google.com/file/d/${substringBefore(vid, '/p')}/preview';
      default:
        return null;
    }
  }

  @override
  Future<List<MVideo>> getVideoList(String data) async {
    _seen = [];
    final parts = data.split('|');
    if (parts.length < 2) return [];
    final pageUrl = parts.sublist(0, parts.length - 1).join('|');
    final idx = int.tryParse(parts.last) ?? -1;
    if (idx < 0) return [];

    String pageBody = '';
    try {
      pageBody =
          (await client
                  .get(Uri.parse(abs(pageUrl)))
                  .timeout(Duration(seconds: 20)))
              .body;
    } catch (_) {
      return [];
    }
    final doc = parseHtml(pageBody);
    final servers = doc.select('#ServerList1 div.divv11');
    if (servers.isEmpty || idx >= servers.length) return [];
    final lis = servers[idx].select('ul.ul-server-position1 li');
    if (lis.isEmpty) return [];

    List<MVideo> videos = [];
    for (var el in lis) {
      final type = (el.attr('type') ?? '').isEmpty
          ? (el.attr('class') ?? '')
          : el.attr('type')!;
      final vid = el.attr('data') ?? '';
      final qualityName = (el.attr('quality-data') ?? '').toUpperCase();
      final embedUrl = serverEmbedUrl(type, vid);
      if (embedUrl == null) continue;
      final quality = qualityName.contains('FHD')
          ? '1080p'
          : qualityName.contains('HD')
              ? '720p'
              : qualityName.contains('SD')
                  ? '480p'
                  : 'Default';
      if (type.toLowerCase() == 'temp' || type.toLowerCase() == 'top4top') {
        videos.add(MVideo(embedUrl, quality, embedUrl, headers: {'Referer': baseUrl}));
        continue;
      }
      final subs = await getSourceVideos(embedUrl, abs(pageUrl));
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
    } catch (_) {}
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
        r'''(https?://[^"'<>\s]+?\.(?:m3u8|mp4)(?:\?[^"'<>\s]*)?)''',
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

Animedar main(MSource source) {
  return Animedar(source: source);
}