import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/source_engine.dart';

/// 端到端：本地 HTTP 服务模拟书源站点，验证引擎搜索真实可用
void main() {
  HttpOverrides.global = null; // flutter_test 默认拦截 HttpClient，这里放行真实网络

  late HttpServer server;
  late int port;
  String? receivedQuery;

  setUp(() async {
    receivedQuery = null;
    final handler = const Pipeline().addMiddleware(logRequests()).addHandler((req) {
      if (req.url.path == 'search' || req.url.path == '/search') {
        receivedQuery = req.url.queryParameters['q'];
        return Response.ok('''
<html><body>
<div class="booklist">
  <div class="item"><a href="/book/1.html"><h2>斗破苍穹</h2></a><span class="author">天蚕土豆</span></div>
  <div class="item"><a href="/book/2.html"><h2>凡人修仙传</h2></a><span class="author">忘语</span></div>
</div>
</body></html>
''', headers: {'content-type': 'text/html; charset=utf-8'});
      }
      if (req.url.path.startsWith('page')) {
        final seg = req.url.pathSegments.last;
        final p = RegExp(r'\d+').firstMatch(seg)?.group(0) ?? seg;
        return Response.ok('''
<div class="booklist">
  <div class="item"><a href="/book/$p.html"><h2>第$p页的书</h2></a><span class="author">作者$p</span></div>
</div>
''');
      }
      return Response.notFound('nf');
    });
    server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
    port = server.port;
  });

  tearDown(() async {
    await server.close(force: true);
  });

  BookSource makeSource(String searchUrl) => BookSource(
        bookSourceUrl: 'http://127.0.0.1:$port',
        bookSourceName: '本地测试源',
        searchUrl: searchUrl,
        ruleSearch: {
          'bookList': '.booklist .item',
          'name': 'h2@text',
          'author': '.author@text',
          'bookUrl': 'a@href',
        },
      );

  test('中文关键词搜索书源真实可用（不编码，服务端收到原文）', () async {
    final engine = BookSourceEngine();
    final source = makeSource('http://127.0.0.1:$port/search?q={{key}}');
    final results = await engine.search(source, '斗破苍穹');
    expect(results, isNotEmpty);
    expect(results.length, 2);
    expect(results.first.name, '斗破苍穹');
    expect(results.first.author, '天蚕土豆');
    expect(results.first.bookUrl, 'http://127.0.0.1:$port/book/1.html');
    // 服务端收到的是原始中文（非百分号编码）
    expect(receivedQuery, '斗破苍穹');
  });

  test('页码列表 <1,2,3> 按页取数', () async {
    final engine = BookSourceEngine();
    final source = makeSource('http://127.0.0.1:$port/page/<1,2,3>');
    final results = await engine.search(source, '测试', page: 2);
    expect(results, isNotEmpty);
    expect(results.first.name, '第2页的书');
  });

  test('{{page}} 与 {{(page-1)*N}} 计算', () async {
    final engine = BookSourceEngine();
    final source = makeSource('http://127.0.0.1:$port/page/{{page}}_x{{(page-1)*20}}');
    final results = await engine.search(source, '测试', page: 3);
    expect(results, isNotEmpty);
    // path 形如 /page/3_x40 → 第3页的书
    expect(results.first.name, '第3页的书');
  });
}
