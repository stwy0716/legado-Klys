/// 注入到无头 WebView（V8）中的 legado 兼容桥。
///
/// 对齐 legado（legado/app/src/main/java/io/legado/app/help/JsExtensions.kt
/// 与 AnalyzeUrl / AnalyzeRule）在书源脚本里使用的运行时环境：
///
///   * 全局对象：java / cookie / source / book / cache / result / key / page / baseUrl
///   * java.ajax / get / post / connect —— 以「同步 XHR」实现，由原生
///     shouldInterceptRequest 接管发请求（绕过 CORS、统一 Cookie/编码）。
///   * source.getVariable/setVariable/getLoginInfo/putLoginInfo
///   * cookie.getCookie/setCookie/removeCookie/getKey
///   * cache / java.put / java.get 跨阶段键值
///   * 编码：base64、hex；时间格式化；deviceID/androidId；UA
///   * startBrowser* / showBrowser* / reLoginView —— 走原生可见 WebView 交互登录
///
/// 该脚本在每个书源的无头 WebView 创建后于「全局作用域」执行一次；
/// 书源的 jsLib / loginUrl 随后也在全局作用域执行（定义全局函数）。
class LegadoBridgeJs {
  static const String code = r'''
(function () {
  if (globalThis.__legadoBridgeReady) return;
  globalThis.__legadoBridgeReady = true;

  var __state = {
    meta: { url: "", name: "", httpUrl: "" },
    variable: "",
    variableComment: "",
    lastUpdateTime: 0,
    loginInfo: "",
    kv: {},
    cookies: {},
    logs: [],
    toasts: [],
    hosts: [],
    browser: [],
    deviceId: "",
    ua: (typeof navigator !== "undefined" && navigator.userAgent) ? navigator.userAgent :
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
  };
  globalThis.__state = __state;
  globalThis.__pendings = {};

  // ---- Rhino（legado 安卓）Java 互操作垫片：V8 无 Java，
  // 让 jsLib 顶部的 JavaImporter/CompatibilityUtils 能安全加载；
  // 真正访问 Packages.xxx 的分支会抛错并被书源自身 try/catch 捕获后回退。----
  function JavaImporterShim() { this.importClass = function () {}; this.importPackage = function () {}; }
  globalThis.JavaImporter = JavaImporterShim;
  globalThis.importClass = function () {};
  globalThis.importPackage = function () {};
  // 同步忙等（对应原版 Packages.java.lang.Thread.sleep：阻塞当前 JS 线程）
  function __sleep(ms) {
    var n = Number(ms);
    if (!(n > 0)) return;
    var end = Date.now() + n;
    while (Date.now() < end) {}
  }
  // 任意 Packages.xxx.yyy 返回可继续取值/调用的代理：
  //   * .sleep(ms) 忙等；new Packages.x() 返回 null（书源自身 try/catch 回退）
  function __pkgProxy() {
    return new Proxy(function () {}, {
      get: function (t, prop) {
        if (prop === 'sleep') return __sleep;
        if (prop === Symbol.toPrimitive || prop === 'toString' || prop === 'valueOf') return function () { return null; };
        return __pkgProxy();
      },
      apply: function () { return null; },
      construct: function () { return null; }
    });
  }
  globalThis.Packages = __pkgProxy();

  function __hostOf(url) {
    if (!url) return "";
    var s = String(url).trim();
    try {
      if (/^https?:\/\//i.test(s)) {
        return new URL(s).host.replace(/:\d+$/, "");
      }
      if (s.indexOf("/") < 0 && s.indexOf(".") >= 0) {
        return s.replace(/:\d+$/, "").replace(/^\/+/, "");
      }
    } catch (e) {}
    return s.replace(/^https?:\/\//i, "").replace(/^\/+/, "").split("/")[0].replace(/:\d+$/, "");
  }

  function __matchCookieHost(host) {
    if (!host) return "";
    if (__state.cookies[host]) return host;
    var keys = Object.keys(__state.cookies);
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i];
      if (host === k || host.endsWith("." + k) || k.endsWith("." + host)) return k;
    }
    return "";
  }

  function __parseCookiePairs(str) {
    var out = {};
    String(str || "").split(/;|\n/).forEach(function (part) {
      var p = part.trim();
      if (!p) return;
      var idx = p.indexOf("=");
      if (idx <= 0) return;
      var name = p.substring(0, idx).trim();
      if (/^(path|domain|expires|max-age|secure|httponly|samesite)$/i.test(name)) return;
      out[name] = p.substring(idx + 1).trim();
    });
    return out;
  }

  function __ingestSetCookie(url, setCookieHeader) {
    if (!setCookieHeader) return;
    var host = __hostOf(url);
    var jar = __parseCookiePairs(__state.cookies[host] || "");
    var fresh = __parseCookiePairs(setCookieHeader);
    Object.keys(fresh).forEach(function (k) { jar[k] = fresh[k]; });
    __state.cookies[host] = Object.keys(jar).map(function (k) { return k + "=" + jar[k]; }).join("; ");
  }

  function __resolve(url, base) {
    var s = String(url == null ? "" : url).trim();
    if (!s) return s;
    if (/^https?:\/\//i.test(s) || s.indexOf("data:") === 0 || s.indexOf("javascript:") === 0) return s;
    if (s.indexOf("//") === 0) return "https:" + s;
    var b = base || __state.meta.httpUrl || "";
    try {
      if (b) return new URL(s, b).toString();
    } catch (e) {}
    return s;
  }

  function __b64Unicode(str) {
    var bytes = new TextEncoder().encode(String(str));
    var bin = "";
    for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin);
  }
  function __unb64Unicode(str) {
    var bin = atob(String(str));
    var bytes = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return new TextDecoder("utf-8").decode(bytes);
  }
  function __hexToBytes(hex) {
    var h = String(hex).replace(/[^0-9a-fA-F]/g, "");
    var out = new Uint8Array(Math.floor(h.length / 2));
    for (var i = 0; i < out.length; i++) out[i] = parseInt(h.substr(i * 2, 2), 16);
    return out;
  }
  function __bytesToHex(bytes) {
    var s = "";
    for (var i = 0; i < bytes.length; i++) s += ("0" + bytes[i].toString(16)).slice(-2);
    return s;
  }

  // ---- AES（基于注入的 aes-js；ECB/CBC + PKCS7，同步）----
  function __b64ToBytes(b64) {
    var bin = atob(String(b64));
    var out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  // 用标准 TextEncoder/Decoder（aes-js 自带 utf8 工具对 4 字节字符处理有缺陷）
  function __utf8ToBytes(s) {
    return new Uint8Array(new TextEncoder().encode(String(s)));
  }
  function __bytesToUtf8(b) {
    return new TextDecoder("utf-8").decode(b);
  }
  function __aesKeyBytes(key) {
    var kb = __utf8ToBytes(String(key));
    var sizes = [16, 24, 32];
    for (var i = 0; i < sizes.length; i++) {
      if (kb.length <= sizes[i]) {
        var out = new Uint8Array(sizes[i]);
        out.set(kb);
        return out;
      }
    }
    return Uint8Array.from(kb.slice(0, 32));
  }
  function __aesIv(iv) {
    var b = __utf8ToBytes(String(iv || ""));
    var out = new Uint8Array(16);
    out.set(b.slice(0, 16));
    return out;
  }
  function __unpadPkcs7(bytes) {
    try {
      var p = bytes[bytes.length - 1];
      if (p > 0 && p <= 16) {
        for (var i = bytes.length - p; i < bytes.length; i++) {
          if (bytes[i] !== p) return bytes;
        }
        return bytes.slice(0, bytes.length - p);
      }
    } catch (e) {}
    return bytes;
  }
  function __aesDecryptToString(data, key, transformation, iv) {
    var cipher = __b64ToBytes(data);
    var kb = __aesKeyBytes(key);
    var mode = String(transformation || "AES/ECB/PKCS7Padding").toUpperCase();
    var dec;
    if (mode.indexOf("CBC") >= 0) {
      dec = new aesjs.ModeOfOperation.cbc(kb, __aesIv(iv)).decrypt(cipher);
    } else {
      dec = new aesjs.ModeOfOperation.ecb(kb).decrypt(cipher);
    }
    dec = __unpadPkcs7(dec);
    return __bytesToUtf8(dec);
  }
  function __aesEncryptToString(text, key, transformation, iv) {
    var kb = __aesKeyBytes(key);
    var data = __utf8ToBytes(String(text));
    var pad = 16 - (data.length % 16);
    var padded = new Uint8Array(data.length + pad);
    padded.set(data);
    for (var i = data.length; i < padded.length; i++) padded[i] = pad;
    var mode = String(transformation || "AES/ECB/PKCS7Padding").toUpperCase();
    var enc;
    if (mode.indexOf("CBC") >= 0) {
      enc = new aesjs.ModeOfOperation.cbc(kb, __aesIv(iv)).encrypt(padded);
    } else {
      enc = new aesjs.ModeOfOperation.ecb(kb).encrypt(padded);
    }
    var bin = "";
    for (var j = 0; j < enc.length; j++) bin += String.fromCharCode(enc[j]);
    return btoa(bin);
  }

  // ============================ cookie ============================
  var cookie = {
    getCookie: function (url) {
      var host = __matchCookieHost(__hostOf(url));
      return host ? (__state.cookies[host] || "") : "";
    },
    setCookie: function (url, cookieStr) {
      var host = __hostOf(url);
      var jar = __parseCookiePairs(__state.cookies[host] || "");
      var add = __parseCookiePairs(cookieStr);
      Object.keys(add).forEach(function (k) { jar[k] = add[k]; });
      __state.cookies[host] = Object.keys(jar).map(function (k) { return k + "=" + jar[k]; }).join("; ");
      return true;
    },
    removeCookie: function (url) {
      var host = __hostOf(url);
      var k = __matchCookieHost(host);
      if (k) delete __state.cookies[k];
      // 返回空串：{{cookie.removeCookie(source.getKey())}} 是「清空 Cookie」惯用法，
      // 会被内插进 URL，返回 true 会拼成 "true/..." 导致地址错误。
      return "";
    },
    getKey: function (url, name) {
      var c = this.getCookie(url);
      var m = String(c).match(new RegExp("(?:^|;\\s*)" + name + "=([^;]*)"));
      return m ? m[1] : "";
    },
    replaceCookie: function (url, c) { return this.setCookie(url, c); }
  };
  globalThis.cookie = cookie;

  // ============================ cache ============================
  var cache = {
    get: function (key) {
      var v = __state.kv[key];
      if (v === undefined || v === null) return null;
      try { return JSON.parse(v); } catch (e) { return v; }
    },
    put: function (key, value) {
      __state.kv[key] = (typeof value === "string") ? value : JSON.stringify(value);
      return true;
    },
    remove: function (key) { delete __state.kv[key]; },
    delete: function (key) { delete __state.kv[key]; }
  };
  globalThis.cache = cache;

  // ============================ source ============================
  var source = {
    getBookSourceUrl: function () { return __state.meta.url; },
    getBookSourceName: function () { return __state.meta.name; },
    getKey: function () { return __state.meta.url; },
    // 变量注释 / 更新时间（部分订阅源以属性方式访问）
    get variableComment() { return __state.variableComment || ""; },
    get lastUpdateTime() { return __state.lastUpdateTime || 0; },
    getVariable: function (key) {
      if (key === undefined || key === null || key === "") return __state.variable;
      try {
        var o = JSON.parse(__state.variable || "{}");
        var v = o[key];
        return v === undefined ? "" : (typeof v === "string" ? v : JSON.stringify(v));
      } catch (e) { return ""; }
    },
    setVariable: function (v) {
      __state.variable = (typeof v === "string") ? v : JSON.stringify(v);
      return __state.variable;
    },
    getLoginInfo: function () { return __state.loginInfo || ""; },
    getLoginInfoMap: function () {
      try {
        var o = JSON.parse(__state.loginInfo || "{}");
        if (o && typeof o === "object" && !Array.isArray(o)) {
          return new Map(Object.entries(o));
        }
      } catch (e) {}
      return new Map();
    },
    setLoginInfo: function (v) {
      __state.loginInfo = (typeof v === "string") ? v : JSON.stringify(v);
      return true;
    },
    putLoginInfo: function (v) {
      __state.loginInfo = (typeof v === "string") ? v : JSON.stringify(v);
      return true;
    },
    getCookie: function (url) { return cookie.getCookie(url); },
    setCookie: function (url, c) { return cookie.setCookie(url, c); },
    removeCookie: function (url) { return cookie.removeCookie(url); },
    // 移除登录头（清空登录信息与由登录派生的状态）
    removeLoginHeader: function () {
      __state.loginInfo = "";
      return true;
    },
    getCookieStore: function () { return cookie; }
  };
  globalThis.source = source;

  function putLoginInfo(info) {
    __state.loginInfo = (typeof info === "string") ? info : JSON.stringify(info);
    return true;
  }
  globalThis.putLoginInfo = putLoginInfo;
  globalThis.setLoginInfo = putLoginInfo;

  // 默认的 getArgument/setArgument（书源 jsLib 通常会自带；缺失时兜底）
  if (typeof globalThis.getArgument !== "function") {
    globalThis.getArgument = function (key) {
      var o = {};
      try { o = JSON.parse(__state.variable || "{}"); } catch (e) { o = {}; }
      return o[key];
    };
  }
  if (typeof globalThis.setArgument !== "function") {
    globalThis.setArgument = function (key, value) {
      var o = {};
      try { o = JSON.parse(__state.variable || "{}"); } catch (e) { o = {}; }
      o[key] = value;
      __state.variable = JSON.stringify(o);
      return __state.variable;
    };
  }

  // ============================ 网络（同步 XHR，原生拦截） ============================
  function __parseUrlOptions(arg, extra) {
    var url = arg, opt = { method: "GET", headers: {}, body: null };
    if (typeof arg === "object" && arg !== null) {
      url = arg.url;
      if (arg.method) opt.method = String(arg.method).toUpperCase();
      if (arg.headers) Object.assign(opt.headers, arg.headers);
      if (arg.body !== undefined && arg.body !== null) opt.body = arg.body;
      if (arg.data !== undefined && arg.data !== null) opt.body = arg.data;
      if (arg.webView) opt.webView = true;
    } else if (typeof arg === "string") {
      var comma = arg.indexOf(",{");
      if (comma >= 0) {
        url = arg.substring(0, comma);
        try {
          var o = JSON.parse(arg.substring(comma + 1));
          if (o.method) opt.method = String(o.method).toUpperCase();
          if (o.headers) Object.assign(opt.headers, o.headers);
          if (o.body !== undefined && o.body !== null) opt.body = o.body;
          if (o.charset) opt.charset = o.charset;
          if (o.webView) opt.webView = true;
        } catch (e) {}
      }
      var m = /,(POST|GET|PUT|DELETE)(?::([\s\S]*))?$/i.exec(url);
      if (m) { url = url.substring(0, m.index); opt.method = m[1].toUpperCase(); if (m[2]) opt.body = m[2]; }
    }
    if (extra && typeof extra === "object") {
      if (extra.method) opt.method = String(extra.method).toUpperCase();
      if (extra.headers) Object.assign(opt.headers, extra.headers);
      if (extra.body !== undefined && extra.body !== null) opt.body = extra.body;
    }
    return { url: url, opt: opt };
  }

  function __doXhrRaw(url, opt, respType) {
    url = __resolve(url);
    var method = opt.method || "GET";
    var headers = {};
    Object.keys(opt.headers || {}).forEach(function (k) {
      if (opt.headers[k] !== undefined && opt.headers[k] !== null) headers[k] = String(opt.headers[k]);
    });
    var bodyStr = null;
    if (opt.body !== undefined && opt.body !== null) {
      bodyStr = (typeof opt.body === "string") ? opt.body : JSON.stringify(opt.body);
    }
    if (bodyStr !== null && method !== "GET" && method !== "HEAD") {
      headers["X-Legado-Body"] = __b64Unicode(bodyStr);
      if (!__hasHeader(headers, "Content-Type")) headers["Content-Type"] = "application/x-www-form-urlencoded";
    }
    if (!__hasHeader(headers, "Cookie") && !__hasHeader(headers, "cookie")) {
      var c = cookie.getCookie(url);
      if (c) headers["Cookie"] = c;
    }
    var x = new XMLHttpRequest();
    x.open(method, url, false);
    Object.keys(headers).forEach(function (k) {
      try { x.setRequestHeader(k, headers[k]); } catch (e) {}
    });
    if (respType === "arraybuffer") x.responseType = "arraybuffer";
    x.send(bodyStr);
    var sc = null;
    try { sc = x.getResponseHeader("X-Set-Cookie"); } catch (e) {}
    if (sc) __ingestSetCookie(url, sc);
    if (__state.hosts.indexOf(__hostOf(url)) < 0) __state.hosts.push(__hostOf(url));
    var resp = respType === "arraybuffer" ? x.response : x.responseText;
    return { status: x.status, text: resp, url: url };
  }

  // 返回 OkHttp Response 风格对象（java.get/post/... 用），保留文本语义
  function __response(raw) {
    var text = raw.text, code = raw.status;
    return {
      body: function () { return text; },
      text: function () { return text; },
      string: function () { return text; },
      statusCode: function () { return code; },
      getResponseCode: function () { return code; },
      isSuccessful: function () { return code >= 200 && code < 300; },
      header: function (name) { return null; },
      headers: function () { return {}; },
      headerMap: function () { return {}; },
      toString: function () { return text; },
      valueOf: function () { return text; },
      raw: text
    };
  }

  // 抛错版（java.ajax 等需要「失败即抛」的语义）
  function __doXhr(url, opt, respType) {
    var r = __doXhrRaw(url, opt, respType);
    if (r.status === 0) throw new Error("网络请求失败: " + r.url);
    if (r.status >= 400) throw new Error("HTTP " + r.status + " " + r.url);
    return r.text;
  }
  function __hasHeader(headers, name) {
    var lk = name.toLowerCase();
    return Object.keys(headers).some(function (k) { return k.toLowerCase() === lk; });
  }

  // ==================== 原生能力通道（同步 XHR -> shouldInterceptRequest） ====================
  // WebView 渲染 / 文件系统 / 压缩包 / 字体解析等能力由 Dart 侧实现，
  // JS 通过同步 XHR 访问 https://legado.native/<路由> 由原生拦截返回结果。
  function __nativeQuery(params) {
    var parts = [];
    Object.keys(params || {}).forEach(function (k) {
      var v = params[k];
      if (v === undefined || v === null || v === "") return;
      parts.push(encodeURIComponent(k) + "=" + encodeURIComponent(String(v)));
    });
    return parts.length ? "?" + parts.join("&") : "";
  }
  function __native(route, params, body) {
    var url = "https://legado.native/" + String(route).replace(/^\//, "") + __nativeQuery(params);
    var opt = { method: body === undefined ? "GET" : "POST", headers: {} };
    var resp = __doXhr(url, opt);
    // 原生返回 {"__error":...} 表示能力调用失败；其余原样透传
    try {
      var o = JSON.parse(resp);
      if (o && typeof o === "object" && o.__error) throw new Error(o.__error);
    } catch (e) {
      if (!(e instanceof SyntaxError)) throw e;
    }
    return resp;
  }

  function __connect(url) {
    var conn = {
      __url: url, __method: "GET", __headers: {}, __body: null,
      headers: function (h) { if (h) Object.keys(h).forEach((k) => { this.__headers[k] = h[k]; }); return this; },
      addHeader: function (k, v) { this.__headers[k] = v; return this; },
      header: function (k, v) { this.__headers[k] = v; return this; },
      method: function (m) { this.__method = String(m).toUpperCase(); return this; },
      setBody: function (b) { this.__body = b; return this; },
      body: function (b) { this.__body = b; this.__method = "POST"; return this; },
      get: function () { this.__method = "GET"; return this; },
      post: function (b) { this.__method = "POST"; if (b !== undefined) this.__body = b; return this; },
      followRedirects: function () { return this; },
      timeout: function () { return this; },
      execute: function () {
        var text = __doXhr(this.__url, { method: this.__method, headers: this.__headers, body: this.__body });
        return {
          code: 200,
          url: this.__url,
          body: function () { return { string: function () { return text; }, bytes: function () { return new TextEncoder().encode(text); }, text: function () { return text; } }; },
          headers: {},
          header: function () { return null; },
          raw: text
        };
      }
    };
    return conn;
  }

  // ============================ 浏览器交互登录 ============================
  function __openBrowser(url, title, awaitFlag) {
    var id = "b" + Date.now() + Math.floor(Math.random() * 1000);
    __state.browser.push({ id: id, url: __resolve(url), title: title || "" });
    return new Promise(function (resolve) {
      __pendings[id] = resolve;
      try {
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler("legadoBrowser", JSON.stringify({
            id: id, url: __resolve(url), title: title || ""
          }));
        }
      } catch (e) {}
      if (!awaitFlag) {
        setTimeout(function () { if (__pendings[id]) { delete __pendings[id]; resolve(""); } }, 0);
      }
    });
  }
  globalThis.__resolveBrowser = function (id, cookieStr, finalUrl) {
    if (cookieStr) __ingestSetCookie(finalUrl || "", cookieStr);
    if (__pendings[id]) { var r = __pendings[id]; delete __pendings[id]; r(cookieStr || ""); }
  };
  globalThis.__cancelBrowser = function (id) {
    if (__pendings[id]) { var r = __pendings[id]; delete __pendings[id]; r(""); }
  };

  // ============================ java ============================
  function __argString(args) {
    return Array.prototype.map.call(args, function (a) {
      if (typeof a === "string") return a;
      try { return JSON.stringify(a); } catch (e) { return String(a); }
    }).join(" ");
  }

  var java = {
    // 日志 / 提示
    log: function () { __state.logs.push(__argString(arguments)); },
    toast: function (msg) { var s = String(msg == null ? "" : msg); __state.toasts.push(s); __state.logs.push(s); },
    longToast: function (msg) { var s = String(msg == null ? "" : msg); __state.toasts.push(s); __state.logs.push(s); },

    // 网络
    ajax: function (url, options) {
      var p = __parseUrlOptions(url, options);
      return __doXhr(p.url, p.opt);
    },
    // 网络：get 需区分「HTTP GET」与「跨阶段变量读取」。
    // 两参或 URL 形参 → HTTP Response；单参非 URL → 变量读取（对齐原版 java.get(key)）。
    get: function (url, headers) {
      var s = String(url == null ? "" : url).trim();
      var isUrl = /^(https?:\/\/|data:|javascript:|\/\/)/i.test(s);
      if (headers === undefined && !isUrl) {
        var v = cache.get(s);
        return v === null ? "" : v;
      }
      return __response(__doXhrRaw(url, { method: "GET", headers: headers || {} }));
    },
    post: function (url, body, headers) {
      return __response(__doXhrRaw(url, { method: "POST", body: body, headers: headers || {} }));
    },
    put: function (url, body, headers) {
      return __response(__doXhrRaw(url, { method: "PUT", body: body, headers: headers || {} }));
    },
    delete: function (url, headers) {
      return __response(__doXhrRaw(url, { method: "DELETE", headers: headers || {} }));
    },
    head: function (url, headers) {
      return __response(__doXhrRaw(url, { method: "HEAD", headers: headers || {} }));
    },
    connect: function (url) { return __connect(url); },
    newResponse: function (url) { return __connect(url); },
    getCookie: function (url) { return cookie.getCookie(url); },

    // 编码
    base64Encode: function (str) { return __b64Unicode(str); },
    base64Decode: function (str) {
      try { return __unb64Unicode(str); } catch (e) {
        try { return atob(str); } catch (e2) { return ""; }
      }
    },
    encodeBase64: function (str) { return __b64Unicode(str); },
    decodeBase64: function (str) { return this.base64Decode(str); },
    hexDecodeToString: function (hex) {
      // 书源对「明文 JSON / HTML」与「十六进制响应」都会调用本函数。
      // 仅当整串为合法、偶数长度、可解出 UTF-8 的十六进制时才解码，否则原样返回。
      var raw = String(hex == null ? "" : hex);
      var h = raw.replace(/\s+/g, "");
      if (h.length === 0 || (h.length % 2) !== 0 || /[^0-9a-fA-F]/.test(h)) return raw;
      try {
        var bytes = new Uint8Array(h.length / 2);
        for (var i = 0; i < bytes.length; i++) bytes[i] = parseInt(h.substr(i * 2, 2), 16);
        return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
      } catch (e) { return raw; }
    },
    hexEncodeToString: function (str) { return __bytesToHex(new TextEncoder().encode(str)); },
    stringToHex: function (str) { return __bytesToHex(new TextEncoder().encode(str)); },

    // 摘要（同步，依赖注入的 __legadoCrypto）
    md5Encode: function (str) {
      var c = globalThis.__legadoCrypto;
      if (!c) throw new Error("md5Encode 不可用（加密库未注入）");
      return c.md5(str);
    },
    md5Encode16: function (str) {
      var c = globalThis.__legadoCrypto;
      if (!c) throw new Error("md5Encode16 不可用（加密库未注入）");
      return c.md5(str).substring(0, 16);
    },
    digestHex: function (data, algorithm) {
      var c = globalThis.__legadoCrypto;
      if (!c) throw new Error("digestHex 不可用（加密库未注入）");
      var a = String(algorithm || "").toUpperCase();
      if (a === "MD5") return c.md5(data);
      if (a === "SHA-1" || a === "SHA1") return c.sha1(data);
      if (a === "SHA-256" || a === "SHA256") return c.sha256(data);
      if (a === "SHA-512" || a === "SHA512") return c.sha512(data);
      return "";
    },
    digestBase64Str: function (data, algorithm) {
      var c = globalThis.__legadoCrypto;
      if (!c) throw new Error("digestBase64Str 不可用（加密库未注入）");
      var a = String(algorithm || "").toUpperCase();
      var hex = "";
      if (a === "MD5") hex = c.md5(data);
      else if (a === "SHA-1" || a === "SHA1") hex = c.sha1(data);
      else if (a === "SHA-256" || a === "SHA256") hex = c.sha256(data);
      else if (a === "SHA-512" || a === "SHA512") hex = c.sha512(data);
      else return "";
      return c.bytesToBase64(c.hexToBytes(hex));
    },
    HMacHex: function (data, algorithm, key) {
      var c = globalThis.__legadoCrypto;
      if (!c) throw new Error("HMacHex 不可用（加密库未注入）");
      return c.hmac(data, key, algorithm);
    },
    HMacBase64: function (data, algorithm, key) {
      var c = globalThis.__legadoCrypto;
      if (!c) throw new Error("HMacBase64 不可用（加密库未注入）");
      return c.bytesToBase64(c.hexToBytes(c.hmac(data, key, algorithm)));
    },
    // 对齐原版 URLEncoder.encode：UTF-8 百分号编码，空格转 '+'
    encodeURI: function (str, enc) {
      var s = String(str == null ? "" : str);
      try {
        return encodeURIComponent(s).replace(/%20/g, "+");
      } catch (e) {
        return "";
      }
    },

    // AES 对称加解密（同步；对齐 legado JsExtensions）
    aesBase64DecodeToString: function (data, key, transformation, iv) {
      return __aesDecryptToString(data, key, transformation, iv);
    },
    aesBase64EncodeToString: function (text, key, transformation, iv) {
      return __aesEncryptToString(text, key, transformation, iv);
    },
    aesDecodeToString: function (data, key, transformation, iv) {
      return __aesDecryptToString(data, key, transformation, iv);
    },
    aesEncodeToString: function (text, key, transformation, iv) {
      return __aesEncryptToString(text, key, transformation, iv);
    },

    // 对称加密统一入口（对齐原版 createSymmetricCrypto）
    createSymmetricCrypto: function (transformation, key, iv) {
      var mode = String(transformation || "").toUpperCase();
      var keyStr = (typeof key === "string") ? key : (key ? __bytesToUtf8(key) : "");
      var ivStr = (typeof iv === "string") ? iv : (iv ? __bytesToUtf8(iv) : "");
      var is3des = mode.indexOf("DESEDE") >= 0 || mode.indexOf("TRIPLEDES") >= 0 || mode.indexOf("3DES") >= 0;
      var isDes = !is3des && mode.indexOf("DES") >= 0;
      var c = globalThis.__legadoCrypto;
      var self = this;
      return {
        decrypt: function (data) {
          if (!c) throw new Error("加密库未注入");
          if (is3des) return c.tripleDes(data, keyStr, ivStr, mode, false);
          if (isDes) return c.des(data, keyStr, ivStr, mode, false);
          return __aesDecryptToString(data, keyStr, mode, ivStr);
        },
        decryptStr: function (data) { return this.decrypt(data); },
        encrypt: function (data) {
          if (!c) throw new Error("加密库未注入");
          if (is3des) return c.tripleDes(data, keyStr, ivStr, mode, true);
          if (isDes) return c.des(data, keyStr, ivStr, mode, true);
          return __aesEncryptToString(data, keyStr, mode, ivStr);
        },
        encryptBase64: function (data) { return this.encrypt(data); },
        encryptHex: function (data) {
          var b64 = this.encrypt(data);
          if (!c) return b64;
          var bin = atob(b64);
          var bytes = new Uint8Array(bin.length);
          for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
          return c.bytesToHex(bytes);
        }
      };
    },

    // UUID / 工具
    randomUUID: function () {
      return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (ch) {
        var r = Math.random() * 16 | 0;
        var v = ch === "x" ? r : (r & 0x3 | 0x8);
        return v.toString(16);
      });
    },
    toURL: function (url, baseUrl) {
      try { return new URL(String(url), baseUrl || "").toString(); }
      catch (e) { return String(url); }
    },
    toNumChapter: function (s) {
      if (s === null || s === undefined) return null;
      var str = String(s);
      // 常见中文数字 → 阿拉伯数字（章节标题规范化）
      var cn = { "零": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9 };
      str = str.replace(/[零一二三四五六七八九十百千万亿]+/g, function (t) {
        if (t.length === 1) return cn[t] !== undefined ? String(cn[t]) : t;
        // 十/百/千/万 简单处理
        var total = 0, cur = 0, unit = 1;
        for (var i = 0; i < t.length; i++) {
          var ch = t[i];
          if (cn[ch] !== undefined) { cur = cn[ch]; }
          else if (ch === "十") { total += (cur === 0 ? 1 : cur) * 10; cur = 0; }
          else if (ch === "百") { total += (cur === 0 ? 1 : cur) * 100; cur = 0; }
          else if (ch === "千") { total += (cur === 0 ? 1 : cur) * 1000; cur = 0; }
          else if (ch === "万") { total = (total + cur) * 10000; cur = 0; }
          else if (ch === "亿") { total = (total + cur) * 100000000; cur = 0; }
        }
        return String(total + cur);
      });
      return str;
    },
    htmlFormat: function (str) {
      var s = String(str == null ? "" : str);
      s = s.replace(/<script[\s\S]*?<\/script>/gi, "");
      s = s.replace(/<style[\s\S]*?<\/style>/gi, "");
      // 保留 img 地址，其余标签去掉，<br>/</p> 转换行
      s = s.replace(/<img[^>]*?src=["']?([^"'\s>]+)["']?[^>]*>/gi, "\n[IMG]$1\n");
      s = s.replace(/<br\s*\/?>/gi, "\n");
      s = s.replace(/<\/p>/gi, "\n\n");
      s = s.replace(/<[^>]+>/g, "");
      s = s.replace(/&nbsp;/gi, " ").replace(/&amp;/gi, "&").replace(/&lt;/gi, "<").replace(/&gt;/gi, ">");
      return s.replace(/\n{3,}/g, "\n\n").trim();
    },
    t2s: function (text) { return __t2s(String(text == null ? "" : text)); },
    s2t: function (text) { return __s2t(String(text == null ? "" : text)); },

    // 并发 ajax（简化：同步顺序执行，返回 StrResponse 数组）
    ajaxAll: function (urlList, skipRateLimit) {
      var out = [];
      var list = (urlList && urlList.length) ? urlList : [];
      for (var i = 0; i < list.length; i++) {
        out.push({ url: String(list[i]), body: java.ajax(list[i]) });
      }
      return out;
    },

    // 非对称加密（RSA，PKCS#1 v1.5）
    createAsymmetricCrypto: function (transformation) {
      var pubKey = "", priKey = "";
      var c = globalThis.__legadoCrypto;
      var self = this;
      function parseSpki(pem) {
        var b64 = String(pem || "").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
        var bin = atob(b64);
        var der = new Uint8Array(bin.length);
        for (var i = 0; i < bin.length; i++) der[i] = bin.charCodeAt(i);
        var ints = [];
        __derIntegers(der, 0, der.length, ints);
        // SPKI 里最后两个 INTEGER 为 modulus 与 exponent
        if (ints.length < 2) throw new Error("RSA 公钥解析失败");
        var n = ints[ints.length - 2];
        var e = ints[ints.length - 1];
        // 去掉前导 0 的模数/指数
        n = n.replace(/^0+/, "") || "0";
        e = e.replace(/^0+/, "") || "0";
        return { n: n, e: e };
      }
      return {
        setPublicKey: function (key) { pubKey = String(key || ""); return this; },
        setPrivateKey: function (key) { priKey = String(key || ""); return this; },
        encrypt: function (data) {
          if (!c) throw new Error("加密库未注入");
          var k = parseSpki(pubKey);
          var bytes = new Uint8Array(new TextEncoder().encode(String(data)));
          return c.bytesToBase64(c.hexToBytes(c.rsaEncrypt(bytes, k.n, k.e)));
        },
        decrypt: function (data) {
          if (!c) throw new Error("加密库未注入");
          var k = parseSpki(priKey);
          var hex = c.bytesToHex(c.b64ToBytes ? c.b64ToBytes(data) : __b64ToBytes(data));
          return c.rsaDecrypt(hex, k.n, k.e);
        }
      };
    },

    // —— 长尾能力：webView 动态页 / 文件 / 压缩包 / 字体反爬 ——
    // 均通过 __native 同步通道由 Dart 侧实现（见 legado_js_runtime.dart）。
    //webView(htmlOrUrl, js?, baseUrl?)：加载网页或 HTML 片段并返回渲染后的 DOM
    webView: function (a, b, c) {
      var s = String(a == null ? "" : a).trim();
      if (!s) throw new Error("webView: 参数为空");
      var isUrl = /^https?:\/\//i.test(s);
      var js = "", base = "";
      var rest = [b, c];
      for (var i = 0; i < 2; i++) {
        var v = rest[i];
        if (typeof v !== "string" || !v.trim()) continue;
        if (!isUrl && /^https?:\/\//i.test(v.trim()) && !base) base = v.trim();
        else if (!js) js = v;
      }
      if (isUrl) return __native("webview", { url: s, js: js, mode: "html" });
      return __native("webview", { js: js, base: base, mode: "html" }, s);
    },
    //webViewGetSource(htmlOrUrl, js?, baseUrl?)：渲染后取页面源码
    webViewGetSource: function (a, b, c) {
      var s = String(a == null ? "" : a).trim();
      if (!s) throw new Error("webViewGetSource: 参数为空");
      var isUrl = /^https?:\/\//i.test(s);
      var js = "", base = "";
      var rest = [b, c];
      for (var i = 0; i < 2; i++) {
        var v = rest[i];
        if (typeof v !== "string" || !v.trim()) continue;
        if (!isUrl && /^https?:\/\//i.test(v.trim()) && !base) base = v.trim();
        else if (!js) js = v;
      }
      if (isUrl) return __native("webview", { url: s, js: js, mode: "source" });
      return __native("webview", { js: js, base: base, mode: "source" }, s);
    },
    //webViewGetOverrideUrl(url)：返回页面重定向/跳转后的最终 URL
    webViewGetOverrideUrl: function (url, js) {
      return __native("webview", {
        url: String(url == null ? "" : url).trim(),
        js: typeof js === "string" ? js : "",
        mode: "overrideUrl"
      });
    },
    //getVerificationCode(url)：获取验证码图片，返回 Base64
    getVerificationCode: function (url) {
      return __native("captcha", { url: String(url == null ? "" : url).trim() });
    },
    //downloadFile(url)：下载到本地缓存目录，返回文件路径
    downloadFile: function (url) {
      return __native("file/download", { url: String(url == null ? "" : url).trim() });
    },
    //cacheFile(str)：写入缓存文件，返回路径（供 jsLib 二次读取）
    cacheFile: function (str) {
      return __native("file/cache", {}, String(str == null ? "" : str));
    },
    //importScript(js)：导入 JS 文件（URL）或直接求值一段 JS
    importScript: function (js) {
      var s = String(js == null ? "" : js);
      var code = /^https?:\/\//i.test(s.trim()) ? __doXhr(s.trim(), { method: "GET" }) : s;
      (0, eval)(code); // 间接 eval：全局作用域求值
      return true;
    },
    //readTxtFile(path)：读取本地文件或 URL 的文本内容
    readTxtFile: function (path) {
      return __native("file/read", { path: String(path == null ? "" : path).trim() });
    },
    getFile: function (path) {
      return __native("file/read", { path: String(path == null ? "" : path).trim() });
    },
    deleteFile: function (path) {
      return __native("file/delete", { path: String(path == null ? "" : path).trim() });
    },
    //unzipFile(zipPath, outPath?)：解压 zip 到目录，返回目录路径
    unzipFile: function (path, outPath) {
      return __native("zip/extract", { path: String(path || ""), out: String(outPath || "") });
    },
    // 7z/RAR 需原生解压库，明确报错让书源回退
    un7zFile: function () { throw new Error("un7zFile 需要 7-Zip 原生库，当前环境不支持"); },
    unrarFile: function () { throw new Error("unrarFile 需要 RAR 原生库，当前环境不支持"); },
    //getZipStringContent(zipPath, entryPath)：读取压缩包内文本条目
    getZipStringContent: function (path, entry) {
      return __native("zip/read", { path: String(path || ""), entry: String(entry || "") });
    },
    //queryTTF(url)：字体反爬，返回「码点hex -> 真实字符」JSON（键兼容 0x 前缀）
    queryTTF: function (url) {
      var m = __native("ttf/query", { url: String(url == null ? "" : url).trim() });
      try {
        var o = JSON.parse(m), out = {};
        if (o && typeof o === "object") {
          Object.keys(o).forEach(function (k) {
            var v = o[k];
            out[k] = v;
            var kk = String(k).toLowerCase().replace(/^0x/, "");
            out[kk] = v;
            out["0x" + kk] = v;
          });
        }
        return JSON.stringify(out);
      } catch (e) { return m; }
    },
    //replaceFont(html, url)：按字体映射把反爬字符还原为真实字符
    replaceFont: function (html, url) {
      var raw = String(html == null ? "" : html);
      try {
        var map = JSON.parse(this.queryTTF(url));
        return raw.replace(/[\s\S]/g, function (ch) {
          var hex = ch.charCodeAt(0).toString(16);
          var v = map[hex] || map["0x" + hex] || map[ch];
          return (typeof v === "string" && v.length) ? v : ch;
        });
      } catch (e) { return raw; }
    },
    getReadBookConfig: function () { return "{}"; },
    getThemeMode: function () { return "light"; },
    getThemeConfig: function () { return "{}"; },

    // 设备 / UA
    deviceID: function () { return __state.deviceId; },
    androidId: function () { return __state.deviceId; },
    getWebViewUA: function () { return __state.ua; },
    getAppVariant: function () { return "android"; },

    // 时间
    timeFormat: function (time, pattern) { return __timeFormat(time, pattern, false); },
    timeFormatUTC: function (time, pattern) { return __timeFormat(time, pattern, true); },

    // 跨阶段键值（java.put/contains/remove；java.get 已并入上面的网络 get 分派）
    put: function (k, v) { cache.put(k, v); return true; },
    contains: function (k) { return Object.prototype.hasOwnProperty.call(__state.kv, k); },
    remove: function (k) { cache.remove(k); },

    // 书源相关
    refreshExplore: function () { return true; },
    refreshBookToc: function () { return true; },
    refreshBook: function () { return true; },

    // 浏览器登录
    startBrowser: function (url, title) { return __openBrowser(url, title, false); },
    startBrowserDp: function (url, title) { return __openBrowser(url, title, false); },
    startBrowserAwait: function (url, title) { return __openBrowser(url, title, true); },
    showBrowser: function (url, title) { return __openBrowser(url, title, true); },
    showReadingBrowser: function (url, title) { return __openBrowser(url, title, true); },
    reLoginView: function (url) { return __openBrowser(url || "", "登录", true); },

    // 环境探测：轻阅读不可用，需抛错让书源走标准分支
    qread: function () { throw new Error("qread 不可用"); },

    // java.lang / java.net 常见静态调用
    lang: {
      Thread: { sleep: function () {} },
      System: { currentTimeMillis: function () { return Date.now(); }, nanoTime: function () { return Date.now() * 1000000; } },
      String: function (v) { return String(v); },
      Integer: { parseInt: function (v) { return parseInt(v, 10); } }
    },
    net: {
      URLEncoder: { encode: function (s) { return encodeURIComponent(String(s)).replace(/%20/g, "+"); } },
      URLDecoder: { decode: function (s) { return decodeURIComponent(String(s).replace(/\+/g, "%20")); } }
    }
  };
  globalThis.java = java;

  // 常用繁简对照表（覆盖高频字，对齐原版 t2s/s2t 的常用子集）
  var __t2sMap = {
    "書":"书","東":"东","車":"车","長":"长","門":"门","們":"们","開":"开","關":"关","國":"国","圖":"图",
    "園":"园","場":"场","塊":"块","報":"报","寫":"写","讀":"读","語":"语","說":"说","話":"话","請":"请",
    "這":"这","那":"那","嗎":"吗","呢":"呢","來":"来","去":"去","見":"见","視":"视","聽":"听","覺":"觉",
    "會":"会","對":"对","發":"发","現":"现","時":"时","間":"间","裡":"里","裡":"里","後":"后","前":"前",
    "過":"过","還":"还","沒":"没","樣":"样","點":"点","頭":"头","體":"体","麼":"么","什":"什","為":"为",
    "無":"无","有":"有","讓":"让","給":"给","從":"从","與":"与","於":"于","並":"并","都":"都","但":"但",
    "而":"而","或":"或","個":"个","些":"些","已":"已","經":"经","歷":"历","題":"题","問":"问","答":"答",
    "動":"动","畫":"画","夢":"梦","覺":"觉","變":"变","龍":"龙","鳳":"凤","鳥":"鸟","馬":"马","魚":"鱼",
    "驚":"惊","歡":"欢","樂":"乐","愛":"爱","情":"情","戀":"恋","親":"亲","新":"新","舊":"旧","戰":"战",
    "鬥":"斗","學":"学","習":"习","師":"师","錢":"钱","銀":"银","買":"买","賣":"卖","錯":"错","誤":"误",
    "記":"记","憶":"忆","認":"认","識":"识","議":"议","論":"论","話":"话","語":"语","詩":"诗","詞":"词",
    "傳":"传","統":"统","網":"网","絡":"络","聯":"联","系":"系","緊":"紧","紅":"红","綠":"绿","藍":"蓝",
    "黃":"黄","黑":"黑","白":"白","數":"数","據":"据","碼":"码","級":"级","別":"别","處":"处","務":"务",
    "業":"业","資":"资","源":"源","檔":"档","案":"案","鍵":"键","盤":"盘","鼠":"鼠","標":"标","顯":"显",
    "頁":"页","圖":"图","層":"层","級":"级","參":"参","觀":"观","聽":"听","覺":"觉","寶":"宝","貝":"贝",
    "測":"测","試":"试","驗":"验","證":"证","覽":"览","瀏":"浏","讀":"读","寫":"写","譯":"译","釋":"释",
    "稱":"称","際":"际","實":"实","際":"际","際":"际","廣":"广","廠":"厂","務":"务","單":"单","雙":"双",
    "條":"条","線":"线","績":"绩","續":"续","繼":"继","絕":"绝","統":"统","細":"细","組":"组","織":"织",
    "總":"总","統":"统","經":"经","濟":"济","設":"设","備":"备","計":"计","劃":"划","說":"说","該":"该"
  };
  var __s2tMap = {};
  Object.keys(__t2sMap).forEach(function (k) { __s2tMap[__t2sMap[k]] = k; });
  function __t2s(s) {
    return s.replace(/[\u4e00-\u9fff]/g, function (c) { return __t2sMap[c] || c; });
  }
  function __s2t(s) {
    return s.replace(/[\u4e00-\u9fff]/g, function (c) { return __s2tMap[c] || c; });
  }

  function __b64ToBytes(s) {
    var bin = atob(String(s));
    var out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  // 递归解析 DER，收集所有 INTEGER（十六进制）
  function __derIntegers(der, start, end, out) {
    var i = start;
    while (i < end) {
      if (i + 2 > end) break;
      var tag = der[i++];
      var b = der[i++];
      var len = b;
      if (b >= 0x80) {
        var n = b & 0x7f;
        len = 0;
        for (var j = 0; j < n; j++) len = (len << 8) | der[i++];
      }
      if (i + len > end) break;
      if (tag === 0x02) {
        var hex = "";
        for (var j = 0; j < len; j++) hex += ("0" + der[i + j].toString(16)).slice(-2);
        out.push(hex);
      } else if (tag === 0x30 || tag === 0x31 || tag === 0x03) {
        var cs = i;
        if (tag === 0x03) cs = i + 1; // BIT STRING 跳过 unused-bits 字节
        __derIntegers(der, cs, i + len, out);
      }
      i += len;
    }
  }

  function __pad(n) { return n < 10 ? "0" + n : "" + n; }
  function __timeFormat(time, pattern, utc) {
    if (!time) return "";
    var d;
    if (typeof time === "number" || /^\d+$/.test(String(time))) {
      var n = Number(time);
      if (n < 1e12) n = n * 1000;
      d = new Date(n);
    } else {
      d = new Date(String(time).replace(/-/g, "/"));
    }
    if (isNaN(d.getTime())) return "";
    var p = pattern || "yyyy-MM-dd HH:mm:ss";
    var Y = utc ? d.getUTCFullYear() : d.getFullYear();
    var M = (utc ? d.getUTCMonth() : d.getMonth()) + 1;
    var D = utc ? d.getUTCDate() : d.getDate();
    var H = utc ? d.getUTCHours() : d.getHours();
    var m = utc ? d.getUTCMinutes() : d.getMinutes();
    var s = utc ? d.getUTCSeconds() : d.getSeconds();
    return p
      .replace(/yyyy/g, "" + Y)
      .replace(/yy/g, ("" + Y).slice(-2))
      .replace(/MM/g, __pad(M))
      .replace(/dd/g, __pad(D))
      .replace(/HH/g, __pad(H))
      .replace(/mm/g, __pad(m))
      .replace(/ss/g, __pad(s));
  }

  // 供原生每次求值前重置「瞬态」输出
  globalThis.__resetTransient = function () {
    __state.logs = [];
    __state.toasts = [];
    __state.hosts = [];
    __state.browser = [];
  };

  // 求值结束后汇总输出
  globalThis.__envelope = function (ret, err) {
    if (ret === undefined) {
      try { ret = globalThis.result; } catch (e) { ret = null; }
    }
    var safeRet;
    try { safeRet = (ret === undefined) ? null : ret; } catch (e) { safeRet = String(ret); }
    return JSON.stringify({
      ret: safeRet,
      variable: __state.variable,
      loginInfo: __state.loginInfo,
      kv: __state.kv,
      cookies: __state.cookies,
      logs: __state.logs,
      toasts: __state.toasts,
      hosts: __state.hosts,
      browser: __state.browser,
      error: err ? ((err && err.stack) ? String(err.stack) : String(err)) : null
    });
  };
})();
''';
}
