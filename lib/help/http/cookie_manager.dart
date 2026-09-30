import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 持久化 Cookie 管理器：按域名存储，解析 Set-Cookie 并落盘（重启不丢）
class CookieManager {
  static final CookieManager _instance = CookieManager._();
  factory CookieManager() => _instance;
  CookieManager._();

  static const String _prefKey = 'cookie_store_v1';

  // host -> (name -> value)
  final Map<String, Map<String, String>> _store = {};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((host, jar) {
            if (jar is Map) {
              _store[host.toString()] =
                  jar.map((k, v) => MapEntry(k.toString(), v.toString()));
            }
          });
        }
      }
    } catch (_) {}
    _loaded = true;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(_store));
    } catch (_) {}
  }

  /// 从响应头解析并保存 cookie
  Future<void> saveFromResponse(String url, List<String>? setCookies) async {
    await _ensureLoaded();
    if (setCookies == null || setCookies.isEmpty) return;
    final host = Uri.parse(url).host;
    final jar = _store.putIfAbsent(host, () => {});
    var changed = false;
    for (final raw in setCookies) {
      final pair = raw.split(';').first;
      final idx = pair.indexOf('=');
      if (idx > 0) {
        final k = pair.substring(0, idx).trim();
        final v = pair.substring(idx + 1).trim();
        if (v.isEmpty) {
          if (jar.remove(k) != null) changed = true;
        } else {
          if (jar[k] != v) changed = true;
          jar[k] = v;
        }
      }
    }
    if (changed) await _persist();
  }

  /// 直接设置 Cookie（登录成功后由 WebView/JS 写入）
  Future<void> setCookie(String url, String? cookieLine) async {
    await _ensureLoaded();
    if (cookieLine == null || cookieLine.isEmpty) return;
    final host = Uri.parse(url).host;
    final jar = _store.putIfAbsent(host, () => {});
    var changed = false;
    for (final part in cookieLine.split(';')) {
      final idx = part.indexOf('=');
      if (idx > 0) {
        final k = part.substring(0, idx).trim();
        final v = part.substring(idx + 1).trim();
        if (jar[k] != v) changed = true;
        jar[k] = v;
      }
    }
    if (changed) await _persist();
  }

  /// 生成请求 Cookie 头
  String? cookieHeader(String url) {
    final host = Uri.parse(url).host;
    final jar = _store[host] ?? _matchDomain(host);
    if (jar == null || jar.isEmpty) return null;
    return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Map<String, String>? _matchDomain(String host) {
    for (final entry in _store.entries) {
      if (host.endsWith(entry.key)) return entry.value;
    }
    return null;
  }

  Future<void> clear() async {
    _store.clear();
    await _persist();
  }

  Future<void> removeHost(String host) async {
    _store.remove(host);
    await _persist();
  }
}
