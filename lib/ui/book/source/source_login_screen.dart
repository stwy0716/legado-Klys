import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as webview;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/http/cookie_manager.dart' as store;
import 'package:legado_md3/help/source/js_mini_eval.dart';

/// 登录行 UI 定义（对齐原版 RowUi）
class LoginRowUi {
  final String name;
  final String type; // text / password / toggle / select / button
  final String? action;
  final List<String> chars;
  final String? defaultValue;
  final String? viewName;

  LoginRowUi({
    required this.name,
    this.type = 'text',
    this.action,
    this.chars = const [],
    this.defaultValue,
    this.viewName,
  });

  static LoginRowUi? fromJson(dynamic j) {
    if (j is! Map) return null;
    final type = (j['type'] ?? 'text').toString();
    final chars = j['chars'];
    final list = <String>[];
    if (chars is List) {
      for (final c in chars) {
        if (c != null) list.add(c.toString());
      }
    }
    return LoginRowUi(
      name: (j['name'] ?? '').toString(),
      type: type,
      action: j['action']?.toString(),
      chars: list,
      defaultValue: j['default']?.toString(),
      viewName: j['viewName']?.toString(),
    );
  }
}

/// 书源登录页：loginUi 为空走 WebView 登录，否则渲染表单（对齐原版 SourceLogin）
class SourceLoginScreen extends StatefulWidget {
  final BookSource source;
  const SourceLoginScreen({super.key, required this.source});

  @override
  State<SourceLoginScreen> createState() => _SourceLoginScreenState();
}

class _SourceLoginScreenState extends State<SourceLoginScreen> {
  bool _loading = true;
  String? _webUrl;
  List<LoginRowUi> _rows = [];
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, bool> _toggles = {};
  final Map<String, String> _selects = {};
  String _currentUrl = '';
  int _progress = 0;
  String _log = '';

  BookSource get _source => widget.source;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final loginUi = (_source.loginUi ?? '').trim();
      if (loginUi.isEmpty) {
        // Web 模式：加载 loginUrl（相对 bookSourceUrl 解析）
        final raw = (_source.loginUrl ?? '').trim();
        if (raw.isEmpty) {
          setState(() { _loading = false; _log = '书源未配置 loginUrl，无法登录'; });
          return;
        }
        var url = raw;
        if (!url.startsWith('http')) {
          url = Uri.parse(_source.bookSourceUrl).resolve(url).toString();
        }
        setState(() { _webUrl = url; _loading = false; });
        return;
      }
      // 表单模式：解析 loginUi JSON（支持 @js: 脚本）
      var jsonText = loginUi;
      if (loginUi.startsWith('@js:')) {
        jsonText = JsMiniEvaluator.eval(loginUi.substring(4)) ?? '';
      } else if (loginUi.startsWith('<js>') && loginUi.endsWith('</js>')) {
        jsonText = JsMiniEvaluator.eval(
                loginUi.substring(4, loginUi.length - 5)) ??
            '';
      }
      final list = jsonDecode(jsonText);
      if (list is List) {
        final rows = <LoginRowUi>[];
        for (final j in list) {
          final row = LoginRowUi.fromJson(j);
          if (row != null && row.name.isNotEmpty) rows.add(row);
        }
        setState(() {
          _rows = rows;
          _loading = false;
        });
        for (final row in rows) {
          _textControllers[row.name] =
              TextEditingController(text: row.defaultValue ?? '');
          _toggles[row.name] = row.defaultValue == 'true';
          if (row.chars.isNotEmpty) _selects[row.name] = row.defaultValue ?? row.chars.first;
        }
      } else {
        setState(() { _loading = false; _log = 'loginUi 不是 JSON 数组'; });
      }
    } catch (e) {
      setState(() { _loading = false; _log = '登录页初始化失败: $e'; });
    }
  }

  /// 保存 WebView Cookie 到持久化 CookieManager
  Future<void> _saveWebCookie(String? url) async {
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return;
    try {
      final webCookies = await webview.CookieManager.instance()
              .getCookies(url: webview.WebUri(url));
      final line = webCookies.map((c) => '${c.name}=${c.value}').join('; ');
      if (line.isNotEmpty) {
        await store.CookieManager().setCookie(url, line);
      }
    } catch (_) {}
  }

  Future<void> _confirmWeb() async {
    // 最终再保存一次当前页 Cookie，然后结束
    await _saveWebCookie(_currentUrl.isEmpty ? _webUrl : _currentUrl);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _runRowAction(LoginRowUi row) async {
    final action = row.action;
    if (action == null || action.isEmpty) return;
    try {
      final loginJs = _getLoginJs();
      final result = JsMiniEvaluator.eval(loginJs.isEmpty ? action : '$loginJs\n$action',
          result: _loginInfoMap().toString());
      setState(() => _log = '按钮执行结果: ${result ?? '(无返回)'}');
    } catch (e) {
      setState(() => _log = '按钮执行失败: $e');
    }
  }

  Map<String, String> _loginInfoMap() {
    final map = <String, String>{};
    for (final row in _rows) {
      switch (row.type) {
        case 'toggle':
          map[row.name] = (_toggles[row.name] ?? false).toString();
          break;
        case 'select':
          map[row.name] = _selects[row.name] ?? row.defaultValue ?? '';
          break;
        default:
          map[row.name] = _textControllers[row.name]?.text ?? '';
      }
    }
    return map;
  }

  String _getLoginJs() {
    final raw = (_source.loginUrl ?? '').trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('@js:')) return raw.substring(4);
    if (raw.startsWith('<js>') && raw.endsWith('</js>')) {
      return raw.substring(4, raw.length - 5);
    }
    return raw;
  }

  Future<void> _confirmForm() async {
    final info = _loginInfoMap();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sourceLoginInfo_${_source.bookSourceUrl}', jsonEncode(info));
      // 执行 loginUrl 里的登录脚本（能力范围内），并尝试调用 login 函数
      final loginJs = _getLoginJs();
      String? out;
      if (loginJs.isNotEmpty) {
        out = JsMiniEvaluator.eval(
            '$loginJs\nif(typeof login=="function"){try{login();}catch(e){}}',
            result: jsonEncode(info));
      }
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('登录信息已保存${out == null ? '' : '，脚本返回: $out'}。抓取时将自动携带。')));
    } catch (e) {
      if (mounted) {
        setState(() => _log = '保存登录信息失败: $e');
      }
    }
  }

  @override
  void dispose() {
    for (final c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('登录 - ${_source.bookSourceName}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_webUrl != null)
            TextButton(
                onPressed: _confirmWeb, child: const Text('确认登录')),
          if (_rows.isNotEmpty)
            FilledButton(onPressed: _confirmForm, child: const Text('登录')),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _webUrl != null
              ? _buildWeb()
              : _buildForm(),
    );
  }

  Widget _buildWeb() {
    return Column(children: [
      if (_progress < 100) LinearProgressIndicator(value: _progress / 100, minHeight: 2),
      Expanded(child: webview.InAppWebView(
        initialUrlRequest: webview.URLRequest(url: webview.WebUri(_webUrl!)),
        initialSettings: webview.InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          mixedContentMode: webview.MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        ),
        onProgressChanged: (c, p) => setState(() => _progress = p),
        onLoadStart: (c, url) {
          setState(() => _currentUrl = url?.toString() ?? '');
        },
        onLoadStop: (c, url) {
          // 页面加载完成即保存该域 Cookie（登录后页面跳转即持久化）
          _saveWebCookie(url?.toString() ?? _currentUrl);
        },
      )),
      const Padding(
        padding: EdgeInsets.all(8),
        child: Text('在页面中完成登录后点右上角"确认登录"；Cookie 将自动保存',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
      ),
    ]);
  }

  Widget _buildForm() {
    if (_rows.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_log.isEmpty ? '书源未配置登录表单（loginUi）' : _log,
            textAlign: TextAlign.center),
      ));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final row in _rows) _buildRow(row),
      if (_log.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_log, style: const TextStyle(fontSize: 12, color: Colors.orange)),
        ),
      const SizedBox(height: 8),
      const Text('登录信息将保存，抓取时自动携带；loginUrl 为脚本时在本引擎能力范围内执行',
          style: TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }

  Widget _buildRow(LoginRowUi row) {
    final title = (row.viewName != null &&
            row.viewName!.isNotEmpty &&
            row.viewName!.length >= 3 &&
            row.viewName!.startsWith("'") &&
            row.viewName!.endsWith("'"))
        ? row.viewName!.substring(1, row.viewName!.length - 1)
        : row.name;
    switch (row.type) {
      case 'button':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: FilledButton.icon(
            onPressed: () => _runRowAction(row),
            icon: const Icon(Icons.play_arrow, size: 18),
            label: Text(title),
          ),
        );
      case 'toggle':
        return SwitchListTile(
          title: Text(title),
          value: _toggles[row.name] ?? false,
          onChanged: (v) => setState(() => _toggles[row.name] = v),
        );
      case 'select':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: DropdownButtonFormField<String>(
            value: _selects[row.name],
            decoration: InputDecoration(labelText: title, border: const OutlineInputBorder()),
            items: [for (final c in row.chars) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _selects[row.name] = v ?? ''),
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TextField(
            controller: _textControllers[row.name],
            obscureText: row.type == 'password',
            decoration: InputDecoration(
                labelText: title, border: const OutlineInputBorder()),
          ),
        );
    }
  }
}
