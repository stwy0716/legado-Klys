import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:legado_md3/help/storage/source_importer.dart';

/// 内置浏览器 - 对齐原版BrowserScreen
class BrowserScreen extends StatefulWidget {
  final String url;
  final String? title;
  const BrowserScreen({super.key, required this.url, this.title});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  InAppWebViewController? _controller;
  final TextEditingController _urlController = TextEditingController();
  int _progress = 0;
  String _currentUrl = '';
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _urlController.text = widget.url;
  }

  Future<void> _importUrl(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.plain,
      ));
      final res = await dio.get<String>(url);
      final r = await SourceImporter.importRaw(res.data ?? '');
      messenger.showSnackBar(
        SnackBar(content: Text(r.isEmpty ? '未识别到有效的书源/订阅源' : r.toString())),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  /// 处理网页里的 legado://import/... 深度链接
  Future<void> _handleDeepLink(String uri) async {
    final u = Uri.tryParse(uri);
    if (u == null) return;
    if (u.host == 'import') {
      final src = u.queryParameters['src'] ?? u.queryParameters['url'] ?? '';
      if (src.isNotEmpty) await _importUrl(src);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? '浏览器', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_currentUrl.toLowerCase().contains('.json'))
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              tooltip: '一键导入书源/订阅源',
              onPressed: () => _importUrl(_currentUrl),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _controller?.reload()),
          PopupMenuButton<String>(onSelected: (v) async {
            if (v == 'copy') { Clipboard.setData(ClipboardData(text: _currentUrl)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('链接已复制'))); }
            if (v == 'external') launchUrl(Uri.parse(_currentUrl), mode: LaunchMode.externalApplication);
            if (v == 'share') Share.share(_currentUrl);
          }, itemBuilder: (_) => const [
            PopupMenuItem(value: 'copy', child: Text('复制链接')),
            PopupMenuItem(value: 'external', child: Text('系统浏览器打开')),
            PopupMenuItem(value: 'share', child: Text('分享')),
          ]),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Row(children: [
            IconButton(iconSize: 20, icon: const Icon(Icons.arrow_back), onPressed: _canGoBack ? () => _controller?.goBack() : null),
            IconButton(iconSize: 20, icon: const Icon(Icons.arrow_forward), onPressed: _canGoForward ? () => _controller?.goForward() : null),
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: TextField(
              controller: _urlController,
              style: const TextStyle(fontSize: 13),
              textInputAction: TextInputAction.go,
              onSubmitted: (v) {
                var url = v.trim();
                if (!url.startsWith('http')) url = 'https://$url';
                _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
              },
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ))),
          ]),
        ),
      ),
      body: Column(children: [
        if (_progress < 100) LinearProgressIndicator(value: _progress / 100, minHeight: 2),
        Expanded(child: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(widget.url)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            useShouldOverrideUrlLoading: true,
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
          ),
          onWebViewCreated: (c) => _controller = c,
          onProgressChanged: (c, p) => setState(() => _progress = p),
          onLoadStart: (c, url) {
            setState(() { _currentUrl = url?.toString() ?? ''; _urlController.text = _currentUrl; });
          },
          onLoadStop: (c, url) async {
            final back = await c.canGoBack();
            final fwd = await c.canGoForward();
            setState(() { _canGoBack = back; _canGoForward = fwd; });
          },
          shouldOverrideUrlLoading: (controller, action) async {
            final url = action.request.url?.toString() ?? '';
            if (url.startsWith('legado://')) {
              _handleDeepLink(url);
              return NavigationActionPolicy.CANCEL;
            }
            return NavigationActionPolicy.ALLOW;
          },
        )),
      ]),
    );
  }
}
