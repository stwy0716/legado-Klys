import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/data/model/rss_article.dart';

/// RSS订阅服务
class RssService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
  ));

  /// 获取RSS源内容
  Future<List<RssArticle>> fetchRss(RssSource source) async {
    final articles = <RssArticle>[];
    try {
      final response = await _dio.get(source.url);
      final content = response.data.toString();

      // 尝试解析RSS
      articles.addAll(_parseRss(content, source));

      // 如果不是RSS，尝试解析Atom
      if (articles.isEmpty) {
        articles.addAll(_parseAtom(content, source));
      }

      // 如果都不是，尝试解析HTML
      if (articles.isEmpty) {
        articles.addAll(_parseHtml(content, source));
      }
    } catch (e) {
      // 解析失败
    }
    return articles;
  }

  /// 解析RSS 2.0
  List<RssArticle> _parseRss(String content, RssSource source) {
    final articles = <RssArticle>[];
    try {
      final doc = html_parser.parse(content);
      final items = doc.querySelectorAll('item');
      for (final item in items) {
        final title = _getElementText(item, 'title');
        final link = _getElementText(item, 'link');
        final description = _getElementText(item, 'description');
        final pubDate = _getElementText(item, 'pubDate');
        final author = _getElementText(item, 'author');
        final category = _getElementText(item, 'category');

        if (title != null && title.isNotEmpty) {
          articles.add(RssArticle(
            title: title,
            link: link ?? '',
            description: _cleanHtml(description ?? ''),
            pubDate: _parseDate(pubDate),
            author: author,
            category: category,
            sourceName: source.name,
            sourceUrl: source.url,
          ));
        }
      }
    } catch (_) {}
    return articles;
  }

  /// 解析Atom
  List<RssArticle> _parseAtom(String content, RssSource source) {
    final articles = <RssArticle>[];
    try {
      final doc = html_parser.parse(content);
      final entries = doc.querySelectorAll('entry');
      for (final entry in entries) {
        final title = _getElementText(entry, 'title');
        final linkEl = entry.querySelector('link');
        final link = linkEl?.attributes['href'] ?? '';
        final summary = _getElementText(entry, 'summary');
        final content = _getElementText(entry, 'content');
        final updated = _getElementText(entry, 'updated');
        final authorEl = entry.querySelector('author name');
        final author = authorEl?.text;

        if (title != null && title.isNotEmpty) {
          articles.add(RssArticle(
            title: title,
            link: link,
            description: _cleanHtml(summary ?? content ?? ''),
            pubDate: _parseDate(updated),
            author: author,
            sourceName: source.name,
            sourceUrl: source.url,
          ));
        }
      }
    } catch (_) {}
    return articles;
  }

  /// 解析HTML（通用网页抓取）
  List<RssArticle> _parseHtml(String content, RssSource source) {
    final articles = <RssArticle>[];
    try {
      final doc = html_parser.parse(content);
      // 尝试常见的文章列表选择器
      final selectors = [
        'article', '.article-item', '.post-item', '.list-item',
        'li.article', 'div.item', '.news-item',
      ];
      for (final selector in selectors) {
        final items = doc.querySelectorAll(selector);
        if (items.isNotEmpty) {
          for (final item in items.take(20)) {
            final titleEl = item.querySelector('h1, h2, h3, h4, a.title, .title a');
            final title = titleEl?.text.trim();
            final link = titleEl?.attributes['href'] ?? item.querySelector('a')?.attributes['href'] ?? '';
            final desc = item.querySelector('.summary, .description, .excerpt, p')?.text.trim();

            if (title != null && title.isNotEmpty) {
              articles.add(RssArticle(
                title: title,
                link: _resolveUrl(source.url, link),
                description: desc ?? '',
                sourceName: source.name,
                sourceUrl: source.url,
              ));
            }
          }
          break;
        }
      }
    } catch (_) {}
    return articles;
  }

  String? _getElementText(dynamic element, String tag) {
    try {
      final el = element.querySelector(tag);
      return el?.text.trim();
    } catch (_) {
      return null;
    }
  }

  String _cleanHtml(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  int? _parseDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      return DateTime.parse(dateStr).millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }

  String _resolveUrl(String base, String url) {
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    try {
      return Uri.parse(base).resolve(url).toString();
    } catch (_) {
      return url;
    }
  }

  /// 测试RSS源是否可用
  Future<bool> testSource(RssSource source) async {
    try {
      final articles = await fetchRss(source);
      return articles.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
