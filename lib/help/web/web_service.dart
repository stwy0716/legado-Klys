import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/replace_rule.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import '../../data/local/app_database.dart';

class WebService {
  final DatabaseService _db = DatabaseService();
  HttpServer? _server;
  int port = 1122;
  bool get isRunning => _server != null;

  Future<void> start({int port = 1122}) async {
    if (_server != null) return;
    this.port = port;
    final router = Router();

    // 书源API
    router.get('/getBookSources', _getBookSources);
    router.get('/getBookSource', _getBookSource);
    router.post('/saveBookSource', _saveBookSource);
    router.post('/saveBookSources', _saveBookSources);
    router.post('/deleteBookSources', _deleteBookSources);

    // 书籍API
    router.get('/getBookshelf', _getBookshelf);
    router.get('/getChapterList', _getChapterList);
    router.get('/getBookContent', _getBookContent);
    router.get('/refreshToc', _refreshToc);
    router.post('/saveBook', _saveBook);
    router.post('/deleteBook', _deleteBook);
    router.post('/saveBookProgress', _saveBookProgress);

    // 封面/图片
    router.get('/cover', _getCover);
    router.get('/image', _getImage);

    // 阅读配置
    router.get('/getReadConfig', _getReadConfig);
    router.post('/saveReadConfig', _saveReadConfig);

    // RSS API
    router.get('/getRssSources', _getRssSources);
    router.post('/saveRssSource', _saveRssSource);
    router.post('/deleteRssSources', _deleteRssSources);

    // 替换规则API
    router.get('/getReplaceRules', _getReplaceRules);
    router.post('/saveReplaceRule', _saveReplaceRule);
    router.post('/deleteReplaceRule', _deleteReplaceRule);

    // Web界面
    router.get('/', _getWebUI);
    router.get('/index.html', _getWebUI);

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<String> get address async => 'http://${await _getLocalIP()}:$port';

  Future<String> _getLocalIP() async {
    try {
      for (final interface in await NetworkInterface.list()) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  Response _jsonResponse(dynamic data, {int statusCode = 200}) {
    return Response(
      statusCode,
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode(data),
    );
  }

  // === 书源API ===
  Future<Response> _getBookSources(Request request) async {
    final sources = await _db.getAllSources();
    return _jsonResponse(sources.map((s) => s.toJson()).toList());
  }

  Future<Response> _getBookSource(Request request) async {
    final url = request.url.queryParameters['bookSourceUrl'] ?? '';
    final source = await _db.getSource(url);
    if (source == null) return _jsonResponse({'error': 'not found'}, statusCode: 404);
    return _jsonResponse(source.toJson());
  }

  Future<Response> _saveBookSource(Request request) async {
    final body = await request.readAsString();
    final source = BookSource.fromJson(jsonDecode(body));
    final existing = await _db.getSource(source.bookSourceUrl);
    if (existing != null) {
      await _db.updateSource(source);
    } else {
      await _db.insertSource(source);
    }
    return _jsonResponse({'success': true});
  }

  Future<Response> _saveBookSources(Request request) async {
    final body = await request.readAsString();
    final List<dynamic> list = jsonDecode(body);
    int count = 0;
    for (final item in list) {
      final source = BookSource.fromJson(item);
      final existing = await _db.getSource(source.bookSourceUrl);
      if (existing != null) {
        await _db.updateSource(source);
      } else {
        await _db.insertSource(source);
      }
      count++;
    }
    return _jsonResponse({'success': true, 'count': count});
  }

  Future<Response> _deleteBookSources(Request request) async {
    final body = await request.readAsString();
    final List<dynamic> urls = jsonDecode(body);
    for (final url in urls) {
      await _db.deleteSource(url.toString());
    }
    return _jsonResponse({'success': true});
  }

  // === 书籍API ===
  Future<Response> _getBookshelf(Request request) async {
    final books = await _db.getAllBooks();
    return _jsonResponse(books.map((b) => b.toJson()).toList());
  }

  Future<Response> _getChapterList(Request request) async {
    final name = request.url.queryParameters['name'] ?? '';
    final author = request.url.queryParameters['author'] ?? '';
    final chapters = await _db.getChapters(name, author);
    return _jsonResponse(chapters.map((c) => {'title': c.title, 'url': c.url, 'index': c.index}).toList());
  }

  Future<Response> _getBookContent(Request request) async {
    final name = request.url.queryParameters['name'] ?? '';
    final author = request.url.queryParameters['author'] ?? '';
    final index = int.tryParse(request.url.queryParameters['index'] ?? '0') ?? 0;
    final chapters = await _db.getChapters(name, author);
    if (index >= chapters.length) return _jsonResponse({'error': 'chapter not found'}, statusCode: 404);
    return _jsonResponse({'title': chapters[index].title, 'content': chapters[index].content ?? ''});
  }

  Future<Response> _refreshToc(Request request) async {
    return _jsonResponse({'success': true, 'message': 'refresh requested'});
  }

  Future<Response> _saveBook(Request request) async {
    final body = await request.readAsString();
    final book = Book.fromJson(jsonDecode(body));
    final existing = await _db.getBook(book.name, book.author);
    if (existing != null) {
      await _db.updateBook(book);
    } else {
      await _db.insertBook(book);
    }
    return _jsonResponse({'success': true});
  }

  Future<Response> _deleteBook(Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body);
    await _db.deleteBook(data['name'], data['author']);
    return _jsonResponse({'success': true});
  }

  Future<Response> _saveBookProgress(Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body);
    await _db.updateReadPosition(
      data['name'],
      data['author'],
      data['chapterIndex'] ?? 0,
      data['pagePos'] ?? 0,
      DateTime.now().millisecondsSinceEpoch,
    );
    return _jsonResponse({'success': true});
  }

  // === 封面/图片 ===
  Future<Response> _getCover(Request request) async {
    final name = request.url.queryParameters['name'] ?? '';
    final author = request.url.queryParameters['author'] ?? '';
    final book = await _db.getBook(name, author);
    if (book?.coverUrl == null) return _jsonResponse({'error': 'no cover'}, statusCode: 404);
    return Response(302, headers: {'Location': book!.coverUrl!});
  }

  Future<Response> _getImage(Request request) async {
    final url = request.url.queryParameters['url'] ?? '';
    if (url.isEmpty) return _jsonResponse({'error': 'no url'}, statusCode: 400);
    return Response(302, headers: {'Location': url});
  }

  // === 阅读配置 ===
  Future<Response> _getReadConfig(Request request) async {
    return _jsonResponse({
      'textSize': 20,
      'bgColor': 0xFFFFF8E1,
      'textColor': 0xFF333333,
      'pageAnim': 0,
    });
  }

  Future<Response> _saveReadConfig(Request request) async {
    return _jsonResponse({'success': true});
  }

  // === RSS API ===
  Future<Response> _getRssSources(Request request) async {
    final sources = await _db.getRssSources();
    return _jsonResponse(sources.map((s) => {'name': s.name, 'url': s.url, 'group': s.group, 'enabled': s.enabled}).toList());
  }

  Future<Response> _saveRssSource(Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body); final source = RssSource(sourceName: data['name'] ?? '', sourceUrl: data['url'] ?? '', sourceGroup: data['group'], enabled: data['enabled'] ?? true);
    await _db.insertRssSource(source);
    return _jsonResponse({'success': true});
  }

  Future<Response> _deleteRssSources(Request request) async {
    final body = await request.readAsString();
    final List<dynamic> ids = jsonDecode(body);
    for (final id in ids) {
      await _db.deleteRssSource(id);
    }
    return _jsonResponse({'success': true});
  }

  // === 替换规则API ===
  Future<Response> _getReplaceRules(Request request) async {
    final rules = await _db.getReplaceRules();
    return _jsonResponse(rules.map((r) => {'id': r.id, 'replaceSummary': r.replaceSummary, 'replaceRule': r.replaceRule, 'replacement': r.replacement, 'enable': r.enable}).toList());
  }

  Future<Response> _saveReplaceRule(Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body); final rule = ReplaceRule(id: data['id'], replaceSummary: data['replaceSummary'] ?? '', replaceRule: data['replaceRule'] ?? '', replacement: data['replacement'] ?? '', enable: data['enable'] ?? true);
    if (rule.id != null) {
      await _db.updateReplaceRule(rule);
    } else {
      await _db.insertReplaceRule(rule);
    }
    return _jsonResponse({'success': true});
  }

  Future<Response> _deleteReplaceRule(Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body);
    await _db.deleteReplaceRule(data['id']);
    return _jsonResponse({'success': true});
  }

  // === Web界面 ===
  Future<Response> _getWebUI(Request request) async {
    return Response(
      200,
      headers: {'Content-Type': 'text/html; charset=utf-8'},
      body: _webUI,
    );
  }

  String get _webUI => '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Legado Web管理</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f5; }
.header { background: #6750A4; color: white; padding: 16px 24px; display: flex; align-items: center; gap: 16px; }
.header h1 { font-size: 20px; }
.tabs { display: flex; background: white; border-bottom: 1px solid #e0e0e0; padding: 0 24px; }
.tab { padding: 12px 20px; cursor: pointer; border-bottom: 2px solid transparent; color: #666; }
.tab.active { color: #6750A4; border-bottom-color: #6750A4; }
.content { padding: 24px; }
.card { background: white; border-radius: 8px; padding: 16px; margin-bottom: 16px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
.card h3 { margin-bottom: 12px; color: #333; }
table { width: 100%; border-collapse: collapse; }
th, td { padding: 10px 12px; text-align: left; border-bottom: 1px solid #eee; }
th { background: #fafafa; font-weight: 600; color: #555; }
tr:hover { background: #f9f9f9; }
.btn { padding: 8px 16px; border: none; border-radius: 4px; cursor: pointer; font-size: 14px; }
.btn-primary { background: #6750A4; color: white; }
.btn-danger { background: #f44336; color: white; }
.btn-sm { padding: 4px 8px; font-size: 12px; }
input, textarea { padding: 8px 12px; border: 1px solid #ddd; border-radius: 4px; font-size: 14px; width: 100%; }
.form-group { margin-bottom: 12px; }
.form-group label { display: block; margin-bottom: 4px; color: #555; font-size: 13px; }
.status { padding: 4px 8px; border-radius: 4px; font-size: 12px; }
.status-on { background: #e8f5e9; color: #2e7d32; }
.status-off { background: #ffebee; color: #c62828; }
</style>
</head>
<body>
<div class="header">
  <h1>Legado Web管理</h1>
  <span style="opacity:0.8;font-size:14px">地址: <span id="addr"></span></span>
</div>
<div class="tabs">
  <div class="tab active" onclick="switchTab('bookshelf')">书架</div>
  <div class="tab" onclick="switchTab('sources')">书源</div>
  <div class="tab" onclick="switchTab('rss')">RSS订阅</div>
  <div class="tab" onclick="switchTab('replace')">替换规则</div>
</div>
<div class="content">
  <div id="bookshelf" class="tab-content">
    <div class="card"><h3>书架书籍</h3><div id="bookshelf-list">加载中...</div></div>
  </div>
  <div id="sources" class="tab-content" style="display:none">
    <div class="card"><h3>书源列表</h3><div id="source-list">加载中...</div></div>
  </div>
  <div id="rss" class="tab-content" style="display:none">
    <div class="card"><h3>RSS订阅源</h3><div id="rss-list">加载中...</div></div>
  </div>
  <div id="replace" class="tab-content" style="display:none">
    <div class="card"><h3>替换规则</h3><div id="replace-list">加载中...</div></div>
  </div>
</div>
<script>
document.getElementById('addr').textContent = window.location.href;
function switchTab(name) {
  document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
  document.querySelectorAll('.tab-content').forEach(t => t.style.display = 'none');
  event.target.classList.add('active');
  document.getElementById(name).style.display = 'block';
  loadData(name);
}
async function loadData(type) {
  try {
    const res = await fetch('/get' + type.charAt(0).toUpperCase() + type.slice(1));
    const data = await res.json();
    if (type === 'bookshelf') renderBookshelf(data);
    else if (type === 'sources') renderSources(data);
    else if (type === 'rss') renderRss(data);
    else if (type === 'replace') renderReplace(data);
  } catch(e) { document.getElementById(type + '-list').innerHTML = '加载失败: ' + e; }
}
function renderBookshelf(books) {
  let html = '<table><tr><th>书名</th><th>作者</th><th>最新章节</th><th>来源</th></tr>';
  books.forEach(b => { html += '<tr><td>' + (b.name||'') + '</td><td>' + (b.author||'') + '</td><td>' + (b.lastChapter||'') + '</td><td>' + (b.originName||'') + '</td></tr>'; });
  html += '</table>';
  document.getElementById('bookshelf-list').innerHTML = html;
}
function renderSources(sources) {
  let html = '<table><tr><th>名称</th><th>URL</th><th>分组</th><th>状态</th></tr>';
  sources.forEach(s => { html += '<tr><td>' + (s.bookSourceName||'') + '</td><td>' + (s.bookSourceUrl||'') + '</td><td>' + (s.bookSourceGroup||'') + '</td><td><span class="status ' + (s.enabled?'status-on':'status-off') + '">' + (s.enabled?'启用':'禁用') + '</span></td></tr>'; });
  html += '</table>';
  document.getElementById('source-list').innerHTML = html;
}
function renderRss(sources) {
  let html = '<table><tr><th>名称</th><th>URL</th><th>分组</th></tr>';
  sources.forEach(s => { html += '<tr><td>' + (s.name||'') + '</td><td>' + (s.url||'') + '</td><td>' + (s.group_name||'') + '</td></tr>'; });
  html += '</table>';
  document.getElementById('rss-list').innerHTML = html;
}
function renderReplace(rules) {
  let html = '<table><tr><th>摘要</th><th>规则</th><th>替换为</th><th>状态</th></tr>';
  rules.forEach(r => { html += '<tr><td>' + (r.replaceSummary||'') + '</td><td>' + (r.replaceRule||'') + '</td><td>' + (r.replacement||'') + '</td><td><span class="status ' + (r.enable?'status-on':'status-off') + '">' + (r.enable?'启用':'禁用') + '</span></td></tr>'; });
  html += '</table>';
  document.getElementById('replace-list').innerHTML = html;
}
loadData('bookshelf');
</script>
</body>
</html>''';
}
