import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/search_book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/replace_rule.dart';
import 'package:legado_md3/help/source/replace_rule_service.dart';
import 'package:legado_md3/help/source/rule_pipeline.dart';
import 'package:legado_md3/help/http/cookie_manager.dart';
import 'package:legado_md3/help/source/js_mini_eval.dart';
import 'package:enough_convert/enough_convert.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Legado书源引擎 - 对齐原版规则格式（CSS / XPath / JSONPath / 正则 / JS子集）
class BookSourceEngine {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    },
  ));

  final ReplaceRuleService _replaceService = ReplaceRuleService();
  late final RulePipeline _pipeline = RulePipeline();

  /// 强制编码（阅读页可切换），null 时自动探测
  String? forcedCharset;
  void setCharset(String? cs) => forcedCharset = cs;

  /// 最近一次请求解码后的原始响应文本（调试页查看用）
  String? lastRawResponse;

  /// 调试日志（环形，最近 120 条）
  final List<String> debugLog = [];
  void _log(String msg) {
    final t = DateTime.now().toIso8601String().substring(11, 19);
    debugLog.add('$t  $msg');
    if (debugLog.length > 120) debugLog.removeAt(0);
  }
  void clearDebugLog() => debugLog.clear();

  // ==================== URL / 请求 ====================

  /// 处理URL中的{{key}}/{{page}}/{{(page-1)*n}}模板
  /// 搜索/发现 URL 模板处理（对齐原版 AnalyzeUrl.replaceKeyPageJs）：
  /// - `{{key}}` / `{{searchKey}}` 替换为原始关键词（不编码，与原版 evalJS("key") 一致）
  /// - `{{page}}` 替换为页码；`{{(page-1)*N}}` 计算偏移
  /// - `<1,2,3>` 页码列表：按 page 取第 page 项，越界取最后一项
  String _processUrlTemplate(String url, String keyword, int page) {
    var result = url
        .replaceAll('{{key}}', keyword)
        .replaceAll('{{searchKey}}', keyword);
    // 页码列表 <1,2,3>（原版 pagePattern），避免与 JS 比较符号冲突：先替换 {{}} 内联后再处理
    result = result.replaceAllMapped(RegExp(r'<([^<>{}]+)>'), (m) {
      final items = m.group(1)!.split(',').map((s) => s.trim()).toList();
      if (items.isEmpty) return m.group(0)!;
      final idx = page - 1;
      return items[idx >= items.length ? items.length - 1 : idx];
    });
    result = result.replaceAll('{{page}}', page.toString());
    final pageCalc = RegExp(r'\{\{\(page-1\)\*(\d+)\}\}');
    result = result.replaceAllMapped(pageCalc, (m) => ((page - 1) * int.parse(m.group(1)!)).toString());
    return result;
  }

  /// 解析URL和选项（原版格式：url,{options} / url,POST:body）
  Map<String, dynamic> _parseUrlWithOptions(String urlStr) {
    var url = urlStr.trim();
    final options = <String, dynamic>{};
    final commaJson = url.indexOf(',{');
    if (commaJson > 0) {
      final optStr = url.substring(commaJson + 1);
      url = url.substring(0, commaJson);
      try {
        final o = jsonDecode(optStr);
        if (o is Map) options.addAll(o.map((k, v) => MapEntry(k.toString(), v)));
      } catch (_) {}
      return {'url': url, 'options': options};
    }
    final m = RegExp(r'^(.+?),(POST|GET|PUT|DELETE)(?::(.*))?$', caseSensitive: false).firstMatch(url);
    if (m != null) {
      url = m.group(1)!.trim();
      options['method'] = m.group(2)!.toUpperCase();
      final b = m.group(3);
      if (b != null && b.isNotEmpty) options['body'] = b;
    }
    return {'url': url, 'options': options};
  }

  /// 发送HTTP请求，[baseUrl] 用于解析相对地址；[source] 提供书源级 header/charset
  Future<String> _fetch(String url,
      {Map<String, dynamic>? options, String? body, String? baseUrl, BookSource? source}) async {
    final parsed = _parseUrlWithOptions(url);
    var finalUrl = parsed['url'] as String;
    final opts = parsed['options'] as Map<String, dynamic>;
    finalUrl = _resolveUrl(finalUrl, baseUrl ?? '');

    final method = (opts['method'] ?? options?['method'] ?? 'GET').toString().toUpperCase();
    Map<String, dynamic>? headers;
    final rawHeaders = opts['headers'] ?? options?['headers'];
    if (rawHeaders is Map) {
      headers = Map<String, dynamic>.from(rawHeaders);
    } else if (rawHeaders is String && rawHeaders.trim().isNotEmpty) {
      try {
        headers = Map<String, dynamic>.from(jsonDecode(rawHeaders));
      } catch (_) {}
    }
    headers ??= {};
    // 书源级 Header 字段：JSON 对象或每行 "Key: value"（可被 URL 内联 headers 覆盖同名项）
    if (source?.header != null && source!.header!.trim().isNotEmpty) {
      headers.addAll(_parseSourceHeader(source.header!));
    }
    // 登录信息中的 Cookie 自动携带（登录页保存的会话）
    final loginInfo = source == null ? null : await _loginInfoFor(source);
    if (loginInfo != null) {
      final loginCookie = loginInfo['Cookie'] ?? loginInfo['cookie'];
      if (loginCookie != null && loginCookie.isNotEmpty) {
        headers.putIfAbsent('Cookie', () => loginCookie);
      }
    }
    headers.putIfAbsent('User-Agent',
        () => 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36');
    // 自动携带同域已保存的 Cookie（搜索->详情->目录->正文 之间保持会话）
    final cookieManager = CookieManager();
    final existCookie = cookieManager.cookieHeader(finalUrl);
    if (existCookie != null && existCookie.isNotEmpty) {
      headers.putIfAbsent('Cookie', () => existCookie);
    }
    // 解码编码：页面强制编码 > 书源级 charset > Content-Type > HTML meta > utf-8 回退
    final charset = forcedCharset ?? source?.charset;
    final dioOptions = Options(
        method: method,
        headers: headers,
        responseType: ResponseType.bytes,
        followRedirects: true,
        validateStatus: (s) => s != null && s < 400);

    _log('$method $finalUrl');
    Response<List<int>> response;
    try {
      if (method == 'POST' || method == 'PUT') {
        final postBody = body ?? opts['body'] ?? options?['body'] ?? '';
        response = method == 'PUT'
            ? await _dio.put(finalUrl, data: postBody, options: dioOptions)
            : await _dio.post(finalUrl, data: postBody, options: dioOptions);
      } else if (method == 'DELETE') {
        response = await _dio.delete(finalUrl, options: dioOptions);
      } else {
        response = await _dio.get(finalUrl, options: dioOptions);
      }
    } catch (e) {
      _log('请求失败: $e');
      rethrow;
    }
    // 保存服务器下发的 Set-Cookie，供后续同域请求使用
    await cookieManager.saveFromResponse(finalUrl, response.headers.map['set-cookie']);
    _log('响应 ${response.statusCode}, ${(response.data ?? []).length} 字节');
    final text = _decodeBytes(response.data ?? [], response.headers.map, fallbackCharset: charset);
    _log('解码完成，文本 ${text.length} 字符');
    lastRawResponse = text;
    return text;
  }

  /// 解析书源 Header 字段：JSON 对象（{"Key":"value"}）或每行 "Key: value"
  Map<String, dynamic> _parseSourceHeader(String raw) {
    final map = <String, dynamic>{};
    var t = raw.trim();
    if (t.isEmpty) return map;
    // @js: / <js> 动态生成 header（对齐原版 getHeaderMap）
    if (t.startsWith('@js:')) {
      t = JsMiniEvaluator.eval(t.substring(4))?.trim() ?? '';
    } else if (t.startsWith('<js>') && t.endsWith('</js>')) {
      t = JsMiniEvaluator.eval(t.substring(4, t.length - 5))?.trim() ?? '';
    }
    if (t.isEmpty) return map;
    try {
      final j = jsonDecode(t);
      if (j is Map) {
        j.forEach((k, v) => map[k.toString()] = v.toString());
        return map;
      }
    } catch (_) {}
    for (final line in t.split('\n')) {
      final i = line.indexOf(':');
      if (i > 0) {
        final k = line.substring(0, i).trim();
        final v = line.substring(i + 1).trim();
        if (k.isNotEmpty) map[k] = v;
      }
    }
    return map;
  }

  /// 按编码解码字节：强制编码 > 书源编码 > Content-Type > HTML meta > utf-8（失败回退 GBK）
  String _decodeBytes(List<int> bytes, Map<String, List<String>> respHeaders, {String? fallbackCharset}) {
    String? cs = fallbackCharset;
    final ct = (respHeaders['content-type'] ?? respHeaders['Content-Type'] ?? []).join(';').toLowerCase();
    final m = RegExp(r'charset=([a-z0-9\-]+)').firstMatch(ct);
    if (m != null) cs ??= m.group(1);
    if (cs == null) {
      final head = String.fromCharCodes(bytes.take(2048).map((b) => b & 0xff)).toLowerCase();
      final mm = RegExp(r"""charset=["']?([a-z0-9\-]+)""").firstMatch(head);
      if (mm != null) cs = mm.group(1);
    }
    cs = cs?.toLowerCase();
    try {
      if (cs == 'gbk' || cs == 'gb2312' || cs == 'gb18030') return GbkCodec().decode(bytes);
      if (cs == 'big5' || cs == 'big-5') return Big5Codec().decode(bytes);
      if (cs == 'latin1' || cs == 'iso-8859-1') return latin1.decode(bytes);
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      try {
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        try {
          return GbkCodec().decode(bytes);
        } catch (_) {
          return latin1.decode(bytes);
        }
      }
    }
  }

  /// 解析相对URL
  String _resolveUrl(String url, String baseUrl) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('data:') || url.startsWith('javascript:')) return url;
    if (baseUrl.isEmpty) return url;
    try {
      final base = Uri.parse(baseUrl);
      return base.resolve(url).toString();
    } catch (_) {
      if (url.startsWith('/') && baseUrl.isNotEmpty) {
        final uri = Uri.parse(baseUrl);
        return '${uri.scheme}://${uri.host}$url';
      }
      return url;
    }
  }

  bool _isJson(String content) {
    final t = content.trim();
    return t.startsWith('{') || t.startsWith('[');
  }

  /// 解析书源 variable 字段为全局变量：JSON 对象 或 每行 key=value
  Map<String, dynamic>? _parseVariable(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final t = raw.trim();
    try {
      final j = jsonDecode(t);
      if (j is Map) return j.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {}
    final map = <String, dynamic>{};
    for (final line in t.split('\n')) {
      final i = line.indexOf('=');
      if (i > 0) {
        final k = line.substring(0, i).trim();
        final v = line.substring(i + 1).trim();
        if (k.isNotEmpty) map[k] = v;
      }
    }
    return map.isEmpty ? null : map;
  }

  /// 提取 jsLib 中的 var/let/const 赋值注入为变量（函数定义需完整 JS 引擎，暂不支持）
  Map<String, dynamic>? _parseJsLibVars(String? jsLib) {
    if (jsLib == null || jsLib.trim().isEmpty) return null;
    final map = <String, dynamic>{};
    final re = RegExp(
        r'(?:var|let|const)\s+([A-Za-z_$][\w$]*)\s*=\s*([^;\n]+);?',
        multiLine: true);
    for (final m in re.allMatches(jsLib)) {
      final v = JsMiniEvaluator.eval(m.group(2)!.trim());
      if (v != null) map[m.group(1)!] = v;
    }
    return map.isEmpty ? null : map;
  }

  /// 读取书源登录信息（登录页保存），Cookie 字段进请求头、其余注入 JS 变量
  Future<Map<String, String>?> _loginInfoFor(BookSource source) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('sourceLoginInfo_${source.bookSourceUrl}');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return null;
  }

  /// 组合书源全局变量：variable 字段 + jsLib 赋值 + 登录信息
  Map<String, dynamic>? _sourceVarsFor(BookSource source) {
    final vars = <String, dynamic>{};
    final v = _parseVariable(source.variable);
    if (v != null) vars.addAll(v);
    final lib = _parseJsLibVars(source.jsLib);
    if (lib != null) vars.addAll(lib);
    return vars.isEmpty ? null : vars;
  }

  /// 登录态校验（对齐原版 loginCheckJs）：响应后执行，结果为空/假视为未登录
  void _checkLogin(String content, BookSource source) {
    final checkJs = (source.loginCheckJs ?? '').trim();
    if (checkJs.isEmpty) return;
    final r = JsMiniEvaluator.eval(checkJs, result: content);
    final t = (r ?? '').trim().toLowerCase();
    // 数字结果：indexOf(...)>=0 表示已登录，<0 未登录
    final n = int.tryParse(t);
    if (n != null) {
      if (n < 0) {
        _log('登录校验未通过($checkJs -> "$r")：书源 ${source.bookSourceName} 可能未登录');
        throw Exception('书源「${source.bookSourceName}」需要登录：请到书源管理中登录后重试');
      }
      return;
    }
    if (t.isEmpty || t == 'false' || t == 'null') {
      _log('登录校验未通过($checkJs -> "$r")：书源 ${source.bookSourceName} 可能未登录');
      throw Exception('书源「${source.bookSourceName}」需要登录：请到书源管理中登录后重试');
    }
  }

  // ==================== 列表提取 ====================

  /// 统一提取书籍列表（自动 HTML / JSON）
  List<Map<String, String>> _extractBookList(String content, Map<String, dynamic> rule, String baseUrl) {
    final listRule = (rule['bookList'] ?? '').toString();
    if (listRule.isEmpty) return [];
    _log('列表规则 bookList=$listRule');
    _pipeline
      ..baseUrl = baseUrl
      ..page = null
      ..keyword = null;

    final reverse = listRule.trim().startsWith('-');
    final isJson = _isJson(content);
    final result = <Map<String, String>>[];

    if (isJson) {
      dynamic json;
      try {
        json = jsonDecode(content);
      } catch (_) {
        _log('列表：JSON 解析失败');
        return [];
      }
      final nodes = _pipeline.selectJsonNodes(json, listRule);
      _log('列表：JSON 命中 ${nodes.length} 项');
      for (final item in nodes) {
        if (item is! Map) continue;
        final b = _bookFromJsonItem(item, rule, baseUrl);
        if (b['name']!.isNotEmpty) result.add(b);
      }
    } else {
      final doc = html_parser.parse(content);
      final elements = _pipeline.selectElements(doc, listRule);
      _log('列表：HTML 命中 ${elements.length} 个元素');
      for (final el in elements) {
        final b = _bookFromElement(el, rule, baseUrl);
        if (b['name']!.isNotEmpty) result.add(b);
      }
    }
    _log('列表：成功提取 ${result.length} 本书');
    if (reverse) return result.reversed.toList();
    return result;
  }

  Map<String, String> _bookFromElement(dom.Element el, Map<String, dynamic> rule, String baseUrl) {
    String? f(String key) {
      final r = rule[key]?.toString() ?? '';
      if (r.isEmpty) return null;
      return _pipeline.fieldFromElement(el, r);
    }

    return {
      'name': (f('name') ?? '').trim(),
      'author': (f('author') ?? '').trim(),
      'coverUrl': _resolveUrl(f('coverUrl') ?? '', baseUrl),
      'bookUrl': _resolveUrl(f('bookUrl') ?? '', baseUrl),
      'intro': (f('intro') ?? '').trim(),
      'kind': (f('kind') ?? '').trim(),
      'lastChapter': (f('lastChapter') ?? '').trim(),
      'wordCount': (f('wordCount') ?? '').trim(),
    };
  }

  Map<String, String> _bookFromJsonItem(dynamic item, Map<String, dynamic> rule, String baseUrl) {
    String? f(String key) {
      final r = rule[key]?.toString() ?? '';
      if (r.isEmpty) return null;
      return _pipeline.fieldFromJson(item, r);
    }

    return {
      'name': (f('name') ?? '').trim(),
      'author': (f('author') ?? '').trim(),
      'coverUrl': _resolveUrl(f('coverUrl') ?? '', baseUrl),
      'bookUrl': _resolveUrl(f('bookUrl') ?? '', baseUrl),
      'intro': (f('intro') ?? '').trim(),
      'kind': (f('kind') ?? '').trim(),
      'lastChapter': (f('lastChapter') ?? '').trim(),
      'wordCount': (f('wordCount') ?? '').trim(),
    };
  }

  List<SearchBook> _toSearchBooks(List<Map<String, String>> books, BookSource source) => books
      .map((b) => SearchBook(
            name: b['name'] ?? '',
            author: b['author'] ?? '',
            coverUrl: b['coverUrl'] ?? '',
            bookUrl: b['bookUrl'] ?? '',
            intro: b['intro'] ?? '',
            kind: b['kind'] ?? '',
            lastChapter: b['lastChapter'] ?? '',
            originName: source.bookSourceName,
            origin: source.bookSourceUrl,
          ))
      .toList();

  // ==================== 公开 API ====================

  /// 搜索书籍
  Future<List<SearchBook>> search(BookSource source, String keyword, {int page = 1}) async {
    if (source.searchUrl == null || source.searchUrl!.isEmpty) return [];
    if (source.ruleSearch == null) return [];
    try {
      final url = _processUrlTemplate(source.searchUrl!, keyword, page);
      _log('搜索URL: $url');
      var srcVars = _sourceVarsFor(source);
    final loginInfo = await _loginInfoFor(source);
    if (loginInfo != null) {
      (srcVars ??= <String, dynamic>{}).addAll(loginInfo);
    }
    _pipeline.sourceVars = srcVars;
      final content = await _fetch(url, baseUrl: source.bookSourceUrl, source: source);
      _checkLogin(content, source);
      final books = _extractBookList(content, source.ruleSearch!, source.bookSourceUrl);
      _log('搜索完成，共 ${books.length} 个结果');
      return _toSearchBooks(books, source);
    } catch (e) {
      _log('搜索异常: $e');
      return [];
    }
  }

  /// 发现书籍（使用第一个发现分类）
  Future<List<SearchBook>> explore(BookSource source, {int page = 1}) async {
    if (source.exploreUrl == null || source.exploreUrl!.isEmpty) return [];
    final firstUrl = _firstExploreUrl(source.exploreUrl!);
    return exploreByUrl(source, firstUrl, page: page);
  }

  /// 按指定发现分类 URL 探索
  Future<List<SearchBook>> exploreByUrl(BookSource source, String exploreUrl, {int page = 1}) async {
    if (source.ruleExplore == null || exploreUrl.isEmpty) return [];
    try {
      final url = _processUrlTemplate(exploreUrl, '', page);
      _log('发现URL: $url');
      var srcVars = _sourceVarsFor(source);
    final loginInfo = await _loginInfoFor(source);
    if (loginInfo != null) {
      (srcVars ??= <String, dynamic>{}).addAll(loginInfo);
    }
    _pipeline.sourceVars = srcVars;
      final content = await _fetch(url, baseUrl: source.bookSourceUrl, source: source);
      _checkLogin(content, source);
      final books = _extractBookList(content, source.ruleExplore!, source.bookSourceUrl);
      _log('发现完成，共 ${books.length} 个结果');
      return _toSearchBooks(books, source);
    } catch (e) {
      _log('发现异常: $e');
      return [];
    }
  }

  /// 从 exploreUrl 配置取第一条具体 URL。
  /// 兼容 "名称:::url"（三冒号）与 "名称::url"（两冒号），
  /// 多行分隔，同行多选项用 &&& 连接（与发现页解析保持一致）。
  String _firstExploreUrl(String exploreUrl) {
    final line = exploreUrl
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (line.isEmpty) return '';
    final firstOpt = line.split('&&&').first.trim();
    final sep3 = firstOpt.indexOf(':::');
    if (sep3 >= 0) return firstOpt.substring(sep3 + 3).trim();
    final sep2 = firstOpt.indexOf('::');
    if (sep2 >= 0) return firstOpt.substring(sep2 + 2).trim();
    return firstOpt;
  }

  /// 获取书籍详情
  Future<Book?> getBookInfo(BookSource source, String bookUrl) async {
    try {
      final rule = source.ruleBookInfo ?? {};
      _log('详情URL: $bookUrl');
      // bookUrlPattern：书籍详情页地址校验（对齐原版）
      final urlPattern = (source.bookUrlPattern ?? '').trim();
      if (urlPattern.isNotEmpty) {
        var pattern = urlPattern;
        if (pattern.length > 2 && pattern.startsWith('/') && pattern.endsWith('/')) {
          pattern = pattern.substring(1, pattern.length - 1);
        }
        try {
          if (!RegExp(pattern).hasMatch(bookUrl)) {
            _log('bookUrlPattern 不匹配: $bookUrl !~ $urlPattern，跳过该书源');
            return null;
          }
        } catch (e) {
          _log('bookUrlPattern 正则无效: $urlPattern ($e)');
        }
      }
      var srcVars = _sourceVarsFor(source);
    final loginInfo = await _loginInfoFor(source);
    if (loginInfo != null) {
      (srcVars ??= <String, dynamic>{}).addAll(loginInfo);
    }
    _pipeline.sourceVars = srcVars;
      final content = await _fetch(bookUrl, baseUrl: source.bookSourceUrl, source: source);
      _checkLogin(content, source);
      _pipeline.baseUrl = source.bookSourceUrl;

      final isJson = _isJson(content);
      String name, author, coverUrl, intro, kind, lastChapter;
      var tocUrl = bookUrl;

      String? field(String key) {
        final r = rule[key]?.toString() ?? '';
        if (r.isEmpty) return null;
        final v = isJson
            ? _pipeline.fieldFromJson(jsonDecode(content), r)
            : _pipeline.extractStringFromRaw(content, r);
        _log('详情字段 $key = ${(v ?? '').length > 60 ? '${v!.substring(0, 60)}...' : v}');
        return v;
      }

      name = (field('name') ?? '').trim();
      author = (field('author') ?? '').trim();
      coverUrl = _resolveUrl(field('coverUrl') ?? '', source.bookSourceUrl);
      // coverDecodeJs：封面解密脚本（对齐原版）
      final coverJs = (source.coverDecodeJs ?? '').trim();
      if (coverJs.isNotEmpty && coverUrl.isNotEmpty) {
        coverUrl = JsMiniEvaluator.eval(coverJs, result: coverUrl) ?? coverUrl;
      }
      intro = field('intro') ?? '';
      kind = field('kind') ?? '';
      lastChapter = field('lastChapter') ?? '';
      final toc = field('tocUrl');
      if (toc != null && toc.isNotEmpty) tocUrl = _resolveUrl(toc, source.bookSourceUrl);

      if (name.isEmpty) {
        _log('详情：未解析到书名（请检查 name 规则或响应是否为登录/验证码页）');
        return null;
      }
      return Book(
        name: name,
        author: author,
        coverUrl: coverUrl,
        intro: intro,
        kind: kind,
        lastChapter: lastChapter,
        noteUrl: tocUrl,
        bookUrl: bookUrl,
        originName: source.bookSourceName,
        origin: source.bookSourceUrl,
      );
    } catch (e) {
      _log('详情异常: $e');
      return null;
    }
  }

  /// 获取章节目录（支持 nextTocUrl 翻页拼接）
  Future<List<BookChapter>> getToc(BookSource source, String tocUrl) async {
    if (source.ruleToc == null) return [];
    final chapters = <BookChapter>[];
    var currentUrl = tocUrl;
    final visited = <String>{};
    try {
      for (var page = 0; page < 20; page++) {
        if (visited.contains(currentUrl)) break;
        visited.add(currentUrl);

        final content = await _fetch(currentUrl, baseUrl: source.bookSourceUrl, source: source);
        _checkLogin(content, source);
        final rule = source.ruleToc!;
        final listRule = (rule['chapterList'] ?? '').toString();
        if (listRule.isEmpty) break;
        var srcVars = _sourceVarsFor(source);
    final loginInfo = await _loginInfoFor(source);
    if (loginInfo != null) {
      (srcVars ??= <String, dynamic>{}).addAll(loginInfo);
    }
    _pipeline.sourceVars = srcVars;
        _pipeline.baseUrl = currentUrl;
        _log('目录第 ${page + 1} 页 URL: $currentUrl');
        _log('目录列表规则 chapterList=$listRule');

        final isJson = _isJson(content);
        final pageChapters = <Map<String, String>>[];
        if (isJson) {
          final json = jsonDecode(content);
          final nodes = _pipeline.selectJsonNodes(json, listRule);
          for (final item in nodes) {
            if (item is! Map) continue;
            pageChapters.add({
              'title': (_pipeline.fieldFromJson(item, rule['chapterName']?.toString() ?? '') ?? '').trim(),
              'url': _resolveUrl(
                  _pipeline.fieldFromJson(item, rule['chapterUrl']?.toString() ?? '') ?? '', currentUrl),
              'isVolume': _pipeline.fieldFromJson(item, rule['isVolume']?.toString() ?? '') ?? '',
            });
          }
        } else {
          final doc = html_parser.parse(content);
          final reverse = listRule.trim().startsWith('-');
          var elements = _pipeline.selectElements(doc, listRule);
          if (reverse) elements = elements.reversed.toList();
          for (final el in elements) {
            String? f(String key) {
              final r = rule[key]?.toString() ?? '';
              return r.isEmpty ? null : _pipeline.fieldFromElement(el, r);
            }
            pageChapters.add({
              'title': (f('chapterName') ?? el.text.trim()).trim(),
              'url': _resolveUrl(f('chapterUrl') ?? el.attributes['href'] ?? '', currentUrl),
              'isVolume': f('isVolume') ?? '',
            });
          }
        }

        for (final c in pageChapters) {
          chapters.add(BookChapter(
            index: chapters.length,
            title: c['title'] ?? '',
            url: c['url'] ?? '',
            isVolume: (c['isVolume'] ?? '') == '1' || (c['isVolume'] ?? '').toLowerCase() == 'true',
          ));
        }
        _log('目录第 ${page + 1} 页提取 ${pageChapters.length} 章，累计 ${chapters.length} 章');

        // 目录下一页
        final nextRule = rule['nextTocUrl']?.toString() ?? '';
        if (nextRule.isEmpty) break;
        final next = isJson
            ? _pipeline.fieldFromJson(jsonDecode(content), nextRule)
            : _pipeline.extractStringFromRaw(content, nextRule);
        _log('目录下一页规则 nextTocUrl=$nextRule => $next');
        if (next == null || next.isEmpty || next == currentUrl) break;
        currentUrl = _resolveUrl(next, currentUrl);
      }

      return chapters.where((c) => c.title.isNotEmpty).toList();
    } catch (e) {
      _log('目录异常: $e');
      return chapters;
    }
  }

  /// 获取正文内容
  Future<String?> getContent(BookSource source, String contentUrl,
      {List<ReplaceRule>? replaceRules}) async {
    if (source.ruleContent == null) return null;
    try {
      final rule = source.ruleContent!;
      final content = await _fetch(contentUrl, baseUrl: source.bookSourceUrl, source: source);
      _checkLogin(content, source);
      var srcVars = _sourceVarsFor(source);
    final loginInfo = await _loginInfoFor(source);
    if (loginInfo != null) {
      (srcVars ??= <String, dynamic>{}).addAll(loginInfo);
    }
    _pipeline.sourceVars = srcVars;
      _pipeline.baseUrl = contentUrl;
      final contentRule = (rule['content'] ?? '').toString();
      if (contentRule.isEmpty) return null;
      _log('正文URL: $contentUrl');
      _log('正文规则 content=$contentRule');

      final isJson = _isJson(content);
      var result = isJson
          ? _pipeline.fieldFromJson(jsonDecode(content), contentRule)
          : _pipeline.extractStringFromRaw(content, contentRule, forceJson: false);
      if (result == null || result.isEmpty) {
        _log('正文：规则未匹配到内容');
        return null;
      }

      // 正文分页：递归抓取 nextContentUrl 拼接（最多 10 页）
      final nextRule = rule['nextContentUrl']?.toString() ?? '';
      if (nextRule.isNotEmpty) {
        _log('正文分页规则 nextContentUrl=$nextRule');
        result = await _appendNextPages(source, content, result, nextRule, contentUrl, 1);
      }
      _log('正文提取完成：${result.length} 字符');

      // 图片正文：规则为 imageContent 时保留 <img>
      final keepImage = rule['imageContent']?.toString() == '1' || rule['imageContent']?.toString() == 'true';

      // 应用替换净化
      if (replaceRules != null && replaceRules.isNotEmpty) {
        result = _replaceService.applyRules(result, replaceRules, scope: source.bookSourceUrl);
      }

      result = keepImage ? _cleanHtmlKeepImages(result) : _cleanHtml(result);
      return result.trim();
    } catch (e) {
      _log('正文异常: $e');
      return null;
    }
  }

  /// 递归拼接分页正文
  Future<String> _appendNextPages(
      BookSource source, String pageContent, String acc, String nextRule, String currentUrl, int depth) async {
    if (depth >= 10) return acc;
    try {
      final isJson = _isJson(pageContent);
      var nextUrl = isJson
          ? _pipeline.fieldFromJson(jsonDecode(pageContent), nextRule)
          : _pipeline.extractStringFromRaw(pageContent, nextRule);
      if (nextUrl == null || nextUrl.isEmpty || nextUrl == currentUrl) return acc;
      nextUrl = _resolveUrl(nextUrl, currentUrl);

      final nextContent = await _fetch(nextUrl, baseUrl: source.bookSourceUrl, source: source);
      _checkLogin(nextContent, source);
      final contentRule = source.ruleContent!['content']?.toString() ?? '';
      final nextIsJson = _isJson(nextContent);
      final part = nextIsJson
          ? _pipeline.fieldFromJson(jsonDecode(nextContent), contentRule)
          : _pipeline.extractStringFromRaw(nextContent, contentRule);
      if (part == null || part.isEmpty) return acc;
      acc = '$acc\n${_cleanHtml(part)}';
      final nnRule = source.ruleContent!['nextContentUrl']?.toString() ?? '';
      if (nnRule.isNotEmpty) {
        return _appendNextPages(source, nextContent, acc, nnRule, nextUrl, depth + 1);
      }
      return acc;
    } catch (_) {
      return acc;
    }
  }

  /// 清理HTML标签（纯文本）
  String _cleanHtml(String html) {
    var h = html;
    h = h.replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '');
    h = h.replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '');
    h = h.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    h = h.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n');
    h = h.replaceAll(RegExp(r'<[^>]+>'), '');
    h = _decodeEntities(h);
    h = h.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return h.trim();
  }

  /// 清理HTML但保留图片地址（漫画/图文章节），每张图单独一行
  String _cleanHtmlKeepImages(String html) {
    var h = html;
    h = h.replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '');
    h = h.replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '');
    final imgs = <String>[];
    h = h.replaceAllMapped(RegExp(r'<img[^>]*>', caseSensitive: false), (m) {
      final tag = m.group(0)!;
      final src = RegExp(r'''(?:src|data-src)=["']?([^"'\s>]+)''').firstMatch(tag)?.group(1);
      if (src != null) imgs.add(src);
      return '\n';
    });
    h = h.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    h = h.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n');
    h = h.replaceAll(RegExp(r'<[^>]+>'), '');
    h = _decodeEntities(h);
    final text = h.trim();
    final imageLines = imgs.join('\n');
    return [text, imageLines].where((s) => s.isNotEmpty).join('\n');
  }

  String _decodeEntities(String s) => s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&hellip;', '…')
      .replaceAll('&mdash;', '—')
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)));
}
