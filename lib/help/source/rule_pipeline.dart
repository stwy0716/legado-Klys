import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'css_selector.dart';
import 'xpath_selector.dart';
import 'json_path.dart';
import 'regex_parser.dart';
import 'js_mini_eval.dart';

/// 规则解析模式
enum RuleMode { auto, css, xpath, json, js, regex, defaultRule }

/// Legado 书源统一规则管线。
///
/// 把项目里已有的 [CssSelector]/[XpathSelector]/[JsonPath]/[RegexParser]/
/// [JsMiniEvaluator] 组合起来，对齐原版 AnalyzeRule 的常用语法：
///
/// * 组合：`||`(或，取第一个非空)、`&&`(链式)、`%%`(按位交叉)、`@@`(取全部并换行合并)
/// * 模式前缀：`@css:`、`@xpath:`、`@json:`、`@js:`、`$.`(JSON)、`//`(XPath)、`:`(正则)
/// * 取值后缀：`@text/@textNodes/@ownText/@html/@all/@href/@src/属性名`
/// * 后处理：`##正则##替换`（可多段；单独 `##正则` 为删除；`###正则` 为只取首个匹配）
/// * JS：结尾 `@js:脚本`、整段 `<js>脚本</js>`、模板内 `{{脚本}}`
/// * 默认(JSoup)语法：`tag.div@class.box!0@text`、`children`、负索引/区间索引
class RulePipeline {
  RulePipeline({this.baseUrl = '', this.keyword, this.page});

  /// 当前书源地址，用于相对 URL 解析
  String baseUrl;
  String? keyword;
  int? page;

  // ============================== 文本级 ==============================

  /// 从一整段响应文本按规则取“字符串列表”
  List<String> extractListFromRaw(String raw, String rule, {bool forceJson = false}) {
    if (rule.trim().isEmpty) return raw.isEmpty ? [] : [raw];
    final combined = _splitCombined(rule);
    if (combined.segments.length <= 1) {
      return _extractSingleChain(raw, rule, forceJson);
    }
    switch (combined.type) {
      case '||': // 或：取第一个非空
        for (final seg in combined.segments) {
          final values = _extractSingleChain(raw, seg.trim(), forceJson);
          if (values.isNotEmpty) return values;
        }
        return [];
      case '%%': // 按位交叉：各段结果按索引交错合并
        final results = combined.segments
            .map((s) => _extractSingleChain(raw, s.trim(), forceJson))
            .toList();
        final merged = <String>[];
        final maxLen = results.fold(0, (m, r) => r.length > m ? r.length : m);
        for (var i = 0; i < maxLen; i++) {
          for (final r in results) {
            if (i < r.length) merged.add(r[i]);
          }
        }
        return merged;
      default: // && 链式：各段结果拼接
        final merged = <String>[];
        for (final seg in combined.segments) {
          merged.addAll(_extractSingleChain(raw, seg.trim(), forceJson));
        }
        return merged;
    }
  }

  /// 从一整段响应文本按规则取首个字符串
  String? extractStringFromRaw(String raw, String rule, {bool forceJson = false}) {
    final list = extractListFromRaw(raw, rule, forceJson: forceJson);
    return list.isEmpty ? null : unescapeHtml(list.first);
  }

  /// 处理不含 `||` 的单条规则链（仍可能含 && / %% / @@ / ## / js）
  List<String> _extractSingleChain(String raw, String rule, bool forceJson) {
    final mode = _detectMode(rule, forceJson: forceJson);

    // 整段 <js>...</js>：把原始内容交给 JS
    final jsWrap = RegExp(r'^<js>([\s\S]*?)</js>$').firstMatch(rule.trim());
    if (jsWrap != null) {
      final r = JsMiniEvaluator.eval(jsWrap.group(1)!,
          result: raw, key: keyword, page: page, baseUrl: baseUrl);
      return _nullEmpty(r);
    }

    // @@ 前缀：保留全部匹配，最后用换行合并为“一个值”
    var core = rule;
    var joinAll = false;
    if (core.startsWith('@@')) {
      joinAll = true;
      core = core.substring(2);
    }

    // 分离 ## 后处理
    final parsed = _splitPostProcess(core);
    core = parsed.selector;

    List<String> values;
    switch (mode) {
      case RuleMode.js:
        final script = core.startsWith('@js:') ? core.substring(4) : core;
        final r = JsMiniEvaluator.eval(script,
            result: raw, key: keyword, page: page, baseUrl: baseUrl);
        values = _nullEmpty(r);
        break;
      case RuleMode.json:
        values = _jsonValues(raw, core, forceJson);
        break;
      case RuleMode.xpath:
        values = _xpathValues(raw, core);
        break;
      case RuleMode.regex:
        values = _regexValues(raw, core);
        break;
      case RuleMode.css:
        values = _cssValues(raw, core);
        break;
      case RuleMode.defaultRule:
        values = _defaultValues(raw, core);
        break;
      case RuleMode.auto:
        values = forceJson || _looksJson(raw) ? _jsonValues(raw, core, true) : _defaultValues(raw, core);
        break;
    }

    // 模板插值 {{...}}
    if (values.isNotEmpty) {
      values = values.map((v) => _interpolate(v, parsed.hasInterpolation ? core : null)).toList();
    }

    // ## 正则后处理
    if (values.isNotEmpty && parsed.ops.isNotEmpty) {
      values = values.map((v) => _applyPostOps(v, parsed.ops)).where((v) => v.isNotEmpty).toList();
    }

    // 结尾 @js: 清洗
    final tailJs = parsed.tailJs;
    if (tailJs != null && values.isNotEmpty) {
      values = values
          .map((v) => JsMiniEvaluator.eval(tailJs, result: v, key: keyword, page: page, baseUrl: baseUrl) ?? v)
          .toList();
    }

    if (joinAll && values.isNotEmpty) return [values.join('\n')];
    return values;
  }

  // ============================== 元素级（HTML 列表） ==============================

  /// 选取列表元素（搜索/发现/目录的列表规则）
  List<dom.Element> selectElements(dom.Node scope, String listRule) {
    var rule = listRule.trim();
    if (rule.isEmpty) return [];
    if (rule.startsWith('-')) rule = rule.substring(1).trim(); // 目录倒序标记
    final combined = _splitCombined(rule);
    if (combined.segments.length <= 1) {
      return _selectElementsSingle(scope, rule);
    }
    final results = <List<dom.Element>>[];
    for (final seg in combined.segments) {
      final els = _selectElementsSingle(scope, seg.trim());
      if (els.isNotEmpty) {
        results.add(els);
        if (combined.type == '||') break;
      }
    }
    if (results.isEmpty) return [];
    if (combined.type == '%%') {
      final merged = <dom.Element>[];
      final maxLen = results.fold(0, (m, r) => r.length > m ? r.length : m);
      for (var i = 0; i < maxLen; i++) {
        for (final r in results) {
          if (i < r.length) merged.add(r[i]);
        }
      }
      return merged;
    }
    final merged = <dom.Element>[];
    for (final r in results) {
      merged.addAll(r);
    }
    return merged;
  }

  /// 单条（不含组合分隔符）元素选择
  List<dom.Element> _selectElementsSingle(dom.Node scope, String rule) {
    final mode = _detectMode(rule);
    final core = _splitPostProcess(rule).selector;
    switch (mode) {
      case RuleMode.css:
        return CssSelector.selectAll(scope, _stripCssPrefix(core));
      case RuleMode.xpath:
        return XpathSelector.selectNodes(scope, _stripXPathPrefix(core))
            .whereType<dom.Element>()
            .toList();
      case RuleMode.defaultRule:
      case RuleMode.auto:
      default:
        // JSON 列表不会走这里
        return _defaultElements(scope, core);
    }
  }

  /// 相对单个 HTML 元素取字段值
  String? fieldFromElement(dom.Element el, String rule) {
    if (rule.trim().isEmpty) return null;
    final list = extractListFromRaw(el.outerHtml, rule);
    return list.isEmpty ? null : unescapeHtml(list.first);
  }

  // ============================== JSON 级 ==============================

  /// 选取 JSON 列表节点
  List<dynamic> selectJsonNodes(dynamic root, String listRule) {
    if (listRule.trim().isEmpty) return root is List ? root : [];
    final combined = _splitCombined(listRule.trim());
    if (combined.segments.length <= 1) {
      return _selectJsonNodesSingle(root, listRule.trim());
    }
    final results = <List<dynamic>>[];
    for (final seg in combined.segments) {
      final nodes = _selectJsonNodesSingle(root, seg.trim());
      if (nodes.isNotEmpty) {
        results.add(nodes);
        if (combined.type == '||') break;
      }
    }
    if (results.isEmpty) return [];
    if (combined.type == '%%') {
      final merged = <dynamic>[];
      final maxLen = results.fold(0, (m, r) => r.length > m ? r.length : m);
      for (var i = 0; i < maxLen; i++) {
        for (final r in results) {
          if (i < r.length) merged.add(r[i]);
        }
      }
      return merged;
    }
    final merged = <dynamic>[];
    for (final r in results) {
      merged.addAll(r);
    }
    return merged;
  }

  /// 单条（不含组合分隔符）JSON 列表选择
  List<dynamic> _selectJsonNodesSingle(dynamic root, String rule) {
    final core = _splitPostProcess(rule).selector;
    final r = JsonPath.select(root, _stripJsonPrefix(core));
    // `$.data` 直接命中数组字段时，select 会把整个数组作为单个命中值返回；
    // 列表规则需要的是数组里的每个节点，故展开一层。
    if (r.length == 1 && r[0] is List) {
      return List<dynamic>.from(r[0] as List);
    }
    return r;
  }

  /// 相对一个 JSON item 取字段
  String? fieldFromJson(dynamic item, String rule) {
    if (rule.trim().isEmpty) return null;
    final r = rule.trim();
    final mode = _detectMode(r);
    final parsed = _splitPostProcess(r);
    String? value;
    if (mode == RuleMode.js || parsed.tailJs != null || r.contains('{{')) {
      // 允许 JS 直接处理 item
      final script = r.startsWith('@js:') ? r.substring(4) : parsed.selector;
      value = JsMiniEvaluator.eval(script,
          result: item is String ? item : jsonEncode(item),
          key: keyword, page: page, baseUrl: baseUrl);
    } else if (parsed.selector.isEmpty) {
      value = item?.toString();
    } else {
      final v = JsonPath.selectFirst(item, _stripJsonPrefix(parsed.selector));
      // 选中对象/数组时输出合法 JSON，标量转字符串
      value = v == null
          ? null
          : (v is Map || v is List ? jsonEncode(v) : v.toString());
    }
    if (value == null) return null;
    value = _applyPostOps(value, parsed.ops);
    final tail = parsed.tailJs;
    if (tail != null) {
      value = JsMiniEvaluator.eval(tail, result: value, key: keyword, page: page, baseUrl: baseUrl) ?? value;
    }
    return value.isEmpty ? null : unescapeHtml(value);
  }

  // ===================== 供异步 JS 引擎复用的公共解析能力 =====================

  /// 解析字段规则为：选择器 / 后处理操作 / 尾部 JS / 是否含 mustache。
  FieldRuleParts parseFieldParts(String rule) {
    final p = _splitPostProcess(rule.trim());
    final ops = <FieldOp>[];
    for (final op in p.ops) {
      switch (op.kind) {
        case _OpKind.remove:
          ops.add(FieldOp('remove', op.pattern, null));
          break;
        case _OpKind.replace:
          ops.add(FieldOp('replace', op.pattern, op.replacement));
          break;
        case _OpKind.match:
          ops.add(FieldOp('match', op.pattern, null));
          break;
      }
    }
    return FieldRuleParts(
      selector: p.selector,
      ops: ops,
      tailJs: p.tailJs,
      hasInterpolation: p.hasInterpolation,
    );
  }

  /// 对取到的原始值执行 ## 后处理操作。
  String applyFieldOps(String value, List<FieldOp> ops) {
    final internal = ops.map((o) {
      switch (o.kind) {
        case 'replace':
          return _PostOp.replace(o.pattern, o.replacement ?? '');
        case 'match':
          return _PostOp.match(o.pattern);
        default:
          return _PostOp.remove(o.pattern);
      }
    }).toList();
    return _applyPostOps(value, internal);
  }

  /// 纯 JSONPath 选择（不含 JS），供引擎在 JS 之外复用。
  dynamic jsonPathFirst(dynamic node, String selector) {
    final s = selector.trim();
    if (s.isEmpty) return node?.toString();
    final v = JsonPath.selectFirst(node, _stripJsonPrefix(s));
    if (v == null) return null;
    return (v is Map || v is List) ? jsonEncode(v) : v.toString();
  }

  // ============================== 各模式实现 ==============================

  /// 解析 HTML/XML 文档，做表格片段修复（对齐原版 XPath 对 </td>/</tr>/</tbody> 的包裹）。
  dom.Document _parseHtml(String raw) {
    var h = raw.trim();
    final low = h.toLowerCase();
    if (low.endsWith('</td>')) {
      h = '<tr>$h</tr>';
    } else if (low.endsWith('</tr>') || low.endsWith('</tbody>')) {
      h = '<table>$h</table>';
    }
    // XML 内容：html 包无 XML 解析器，直接按 HTML 解析（对多数书源够用）
    return html_parser.parse(h);
  }

  List<String> _cssValues(String raw, String rule) {
    final doc = _parseHtml(raw);
    final clean = _stripCssPrefix(rule);
    // 分离最后一个顶层 @ 取值后缀
    final at = _lastTopAt(clean);
    final selector = at < 0 ? clean : clean.substring(0, at);
    final getter = at < 0 ? 'text' : clean.substring(at + 1);
    final elements = selector.isEmpty
        ? doc.querySelectorAll('*').where((e) => e.children.isEmpty).toList()
        : CssSelector.selectAll(doc, selector);
    return elements.map((e) => _getByGetter(e, getter)).where((s) => s.isNotEmpty).toList();
  }

  List<String> _xpathValues(String raw, String rule) {
    final doc = _parseHtml(raw);
    return XpathSelector.selectTextFromNode(doc, _stripXPathPrefix(rule));
  }

  List<String> _defaultValues(String raw, String rule) {
    final doc = _parseHtml(raw);
    final steps = _splitSteps(rule);
    if (steps.isEmpty) return [];
    List<dom.Node> current = [doc];
    for (var i = 0; i < steps.length - 1; i++) {
      final next = <dom.Element>[];
      for (final el in current) {
        next.addAll(_elementsSingle(el, steps[i]));
      }
      current = next;
      if (current.isEmpty) return [];
    }
    final getter = steps.last;
    return current.whereType<dom.Element>().map((e) => _getByGetter(e, getter)).where((s) => s.isNotEmpty).toList();
  }

  /// 默认(JSoup)模式选取元素（不包含取值步骤）
  List<dom.Element> _defaultElements(dom.Node scope, String rule) {
    final steps = _splitSteps(rule);
    if (steps.isEmpty) return [];
    // 若最后一步是已知 getter 或属性名，则不作为元素筛选
    final knownGetters = {'text', 'textNodes', 'ownText', 'html', 'all'};
    final lastIsGetter = knownGetters.contains(steps.last) || _looksLikeAttr(steps.last);
    final selectSteps = lastIsGetter ? steps.sublist(0, steps.length - 1) : steps;
    List<dom.Node> current = [scope];
    for (final step in selectSteps) {
      final next = <dom.Element>[];
      for (final el in current) {
        next.addAll(_elementsSingle(el, step));
      }
      current = next;
      if (current.isEmpty) break;
    }
    return current.whereType<dom.Element>().toList();
  }

  bool _looksLikeAttr(String step) {
    // 属性 getter 只能是纯标识符（可含连字符），如 href/src/title/data-id；
    // 含 . # [ 空格 > : 等 CSS/步骤特征的一律视为选择步骤，而非 getter。
    if (step.startsWith(RegExp(r'(class|tag|id|text|children)\.'))) return false;
    if (step == 'children') return false;
    return RegExp(r'^[A-Za-z_][\w-]*$').hasMatch(step);
  }

  /// 单步选择：class.x / tag.x / id.x / text.x / children / 原生 CSS，
  /// 支持完整索引：.N / !N / .-1:10:2（多索引）/ [start:end:step]（区间，含负索引与反向）/ [!...]（排除）。
  List<dom.Element> _elementsSingle(dom.Node temp, String step) {
    var rule = step.trim();
    if (rule.isEmpty) return _childrenOf(temp);

    final idx = _parseIndex(rule);
    final before = idx.before.trim();

    List<dom.Element> elements;
    final parts = before.split('.');
    if (before.isEmpty || before == 'children') {
      elements = _childrenOf(temp);
    } else if (parts.length >= 2) {
      switch (parts[0]) {
        case 'class':
          elements = _byClassName(temp, parts.sublist(1).join('.'));
          break;
        case 'tag':
          elements = _byTagName(temp, parts[1]);
          break;
        case 'id':
          final el = temp is dom.Document
              ? temp.getElementById(parts[1])
              : _getById(temp as dom.Element, parts[1]);
          elements = el == null ? [] : [el];
          break;
        case 'text':
          // 对齐原版 getElementsContainingOwnText：ownText 包含指定文本
          final needle = parts.sublist(1).join('.');
          elements = CssSelector.selectAll(temp, '*')
              .where((e) => _ownText(e).contains(needle))
              .toList();
          break;
        default:
          elements = CssSelector.selectAll(temp, before);
      }
    } else {
      // 单个词当作原生 CSS（如 div.booklist / a.title）
      elements = CssSelector.selectAll(temp, before);
    }

    if (idx.entries.isEmpty) return elements;
    return _applyIndexes(elements, idx.entries, idx.exclude);
  }

  /// 元素自身文本（直接文本节点，不含子元素），对齐 jsoup ownText()
  String _ownText(dom.Element el) => el.nodes
      .where((n) => n.nodeType == dom.Node.TEXT_NODE)
      .map((n) => n.text ?? '')
      .join('');

  /// 解析元素索引（对齐原版 ElementsSingle.findIndexSet）。
  _IndexResult _parseIndex(String rule) {
    final r = rule.trim();
    var before = r;
    var exclude = false;
    final entries = <dynamic>[];

    // [index,...] 形式（含区间 start:end:step 与 ! 排除）
    if (r.endsWith(']')) {
      final open = r.lastIndexOf('[');
      if (open >= 0) {
        before = r.substring(0, open);
        var inner = r.substring(open + 1, r.length - 1);
        if (inner.startsWith('!')) {
          exclude = true;
          inner = inner.substring(1);
        }
        for (final part in inner.split(',')) {
          final p = part.trim();
          if (p.isEmpty) continue;
          final seg = p.split(':');
          if (seg.length >= 3) {
            entries.add((
              int.tryParse(seg[0].trim()),
              int.tryParse(seg[1].trim()),
              int.tryParse(seg[2].trim()) ?? 1,
            ));
          } else if (seg.length == 2) {
            entries.add((int.tryParse(seg[0].trim()), int.tryParse(seg[1].trim()), 1));
          } else {
            final n = int.tryParse(p);
            if (n != null) entries.add(n);
          }
        }
        return _IndexResult(before, exclude, entries);
      }
    }

    // 阅读原版：逆向扫描，遇 . / ! 为索引分隔，: 为多索引分隔（. -1:10:2 / !0:3）
    var i = r.length - 1;
    var numStr = '';
    var isNeg = false;
    var split = '';
    var found = false;
    while (i >= 0) {
      final c = r[i];
      if (c == ' ') {
        i--;
        continue;
      }
      if (c == '-') {
        isNeg = true;
        i--;
        continue;
      }
      final code = c.codeUnitAt(0);
      if (code >= 0x30 && code <= 0x39) {
        numStr = c + numStr;
        i--;
        continue;
      }
      if (c == '!' || c == '.' || c == ':') {
        if (numStr.isNotEmpty || isNeg) {
          final n = int.tryParse(numStr) ?? 0;
          entries.insert(0, isNeg ? -n : n);
          numStr = '';
          isNeg = false;
        }
        if (c != ':') {
          split = c;
          before = r.substring(0, i);
          found = true;
          break;
        }
        i--;
        continue;
      }
      break; // 非索引结构
    }
    if (!found) {
      before = r;
      entries.clear();
    }
    exclude = split == '!';
    return _IndexResult(before, exclude, entries);
  }

  /// 按索引集合筛选元素（含负索引、区间、反向、排除）
  List<dom.Element> _applyIndexes(
      List<dom.Element> elements, List<dynamic> entries, bool exclude) {
    final len = elements.length;
    if (len == 0) return [];
    final indexSet = <int>{};
    for (final entry in entries) {
      if (entry is int) {
        final real = entry < 0 ? entry + len : entry;
        if (real >= 0 && real < len) indexSet.add(real);
      } else if (entry is (int?, int?, int)) {
        var start = entry.$1 ?? 0;
        var end = entry.$2 ?? (len - 1);
        var step = entry.$3;
        if (start < 0) start += len;
        if (end < 0) end += len;
        if (start < 0) start = 0;
        if (end < 0) end = 0;
        if (start >= len) start = len - 1;
        if (end >= len) end = len - 1;
        if (step == 0) step = 1;
        if (start == end) {
          indexSet.add(start);
          continue;
        }
        if (step > 0) {
          for (var x = start; x <= end; x += step) {
            indexSet.add(x);
          }
        } else {
          for (var x = start; x >= end; x += step) {
            indexSet.add(x);
          }
        }
      }
    }
    if (exclude) {
      final picked = <dom.Element>[];
      for (var x = 0; x < len; x++) {
        if (!indexSet.contains(x)) picked.add(elements[x]);
      }
      return picked;
    }
    final picked = <dom.Element>[];
    for (final x in indexSet) {
      if (x >= 0 && x < len) picked.add(elements[x]);
    }
    return picked;
  }

  dom.Element? _getById(dom.Element root, String id) {
    for (final e in root.querySelectorAll('*')) {
      if (e.id == id) return e;
    }
    return null;
  }

  List<dom.Element> _childrenOf(dom.Node n) {
    if (n is dom.Document) return n.documentElement?.children ?? const [];
    if (n is dom.Element) return n.children;
    return const [];
  }

  List<dom.Element> _byClassName(dom.Node n, String cls) {
    if (n is dom.Document) return n.getElementsByClassName(cls);
    if (n is dom.Element) return n.getElementsByClassName(cls);
    return const [];
  }

  List<dom.Element> _byTagName(dom.Node n, String tag) {
    if (n is dom.Document) return n.getElementsByTagName(tag);
    if (n is dom.Element) return n.getElementsByTagName(tag);
    return const [];
  }

  /// 按 getter 从元素取值
  String _getByGetter(dom.Element el, String getter) {
    switch (getter) {
      case 'text':
        return el.text.trim();
      case 'textNodes':
        return el.nodes
            .where((n) => n.nodeType == dom.Node.TEXT_NODE)
            .map((n) => n.text?.trim() ?? '')
            .where((s) => s.isNotEmpty)
            .join('\n');
      case 'ownText':
        return el.nodes
            .where((n) => n.nodeType == dom.Node.TEXT_NODE)
            .map((n) => n.text?.trim() ?? '')
            .join('')
            .trim();
      case 'html':
        el.querySelectorAll('script,style').forEach((e) => e.remove());
        return el.innerHtml.trim();
      case 'all':
      case 'outerHtml':
        return el.outerHtml.trim();
      default:
        if (getter.startsWith('attr:')) return el.attributes[getter.substring(5)] ?? '';
        // 属性名
        return el.attributes[getter] ?? el.text.trim();
    }
  }

  List<String> _jsonValues(String raw, String rule, bool forceJson) {
    dynamic json;
    try {
      json = jsonDecode(raw);
    } catch (_) {
      return [];
    }
    final values = JsonPath.select(json, _stripJsonPrefix(rule));
    return values.map((e) => e == null ? '' : e.toString()).where((s) => s.isNotEmpty).toList();
  }

  List<String> _regexValues(String raw, String rule) {
    var pattern = rule.startsWith(':') ? rule.substring(1) : rule;
    // :正则$group 或 :正则!!序号
    int group = 0;
    final gm = RegExp(r'^(.*?)(?:\$(\d+)|!!(\d+))$', dotAll: true).firstMatch(pattern);
    if (gm != null) {
      pattern = gm.group(1)!;
      group = int.tryParse(gm.group(2) ?? gm.group(3) ?? '0') ?? 0;
    }
    final matches = RegExp(pattern, multiLine: true, dotAll: true).allMatches(raw);
    final out = <String>[];
    for (final m in matches) {
      final g = group <= m.groupCount ? m.group(group) : m.group(0);
      if (g != null && g.isNotEmpty) out.add(g);
    }
    return out;
  }

  // ============================== 后处理 ==============================

  _ParsedRule _splitPostProcess(String rule) {
    final result = _ParsedRule();
    // 提取结尾 @js:
    final jsIdx = _findTop(rule, '@js:');
    var body = rule;
    if (jsIdx >= 0) {
      result.tailJs = rule.substring(jsIdx + 4);
      body = rule.substring(0, jsIdx);
    }
    // 提取 <js></js> 结尾
    final wrap = RegExp(r'<js>([\s\S]*?)</js>$').firstMatch(body);
    if (wrap != null) {
      result.tailJs = wrap.group(1);
      body = body.substring(0, wrap.start);
    }
    result.hasInterpolation = body.contains('{{');
    // 切 ## 链（顶层）
    final parts = _splitByHash(body);
    result.selector = parts.first;
    for (var i = 1; i < parts.length;) {
      var p = parts[i];
      if (p.startsWith('#')) {
        // ###regex：只保留首个匹配
        result.ops.add(_PostOp.match(p.substring(1)));
        i += 1;
      } else if (i + 1 < parts.length) {
        result.ops.add(_PostOp.replace(p, parts[i + 1]));
        i += 2;
      } else {
        result.ops.add(_PostOp.remove(p));
        i += 1;
      }
    }
    return result;
  }

  String _applyPostOps(String value, List<_PostOp> ops) {
    var v = value;
    for (final op in ops) {
      switch (op.kind) {
        case _OpKind.remove:
          v = v.replaceAll(RegExp(op.pattern, multiLine: true, dotAll: true), '');
          break;
        case _OpKind.replace:
          v = RegexParser.replace(v, op.pattern, op.replacement!);
          break;
        case _OpKind.match:
          final m = RegExp(op.pattern, multiLine: true, dotAll: true).firstMatch(v);
          v = m?.group(0) ?? '';
          break;
      }
    }
    return v.trim();
  }

  /// 模板插值：'前缀{{脚本}}后缀'
  String _interpolate(String value, String? template) {
    if (template == null || !template.contains('{{')) return value;
    return template.replaceAllMapped(RegExp(r'\{\{([\s\S]*?)\}\}'), (m) {
      final script = m.group(1)!;
      return JsMiniEvaluator.eval(script, result: value, key: keyword, page: page, baseUrl: baseUrl) ?? '';
    });
  }

  // ============================== 工具方法 ==============================

  RuleMode _detectMode(String rule, {bool forceJson = false}) {
    final r = rule.trim();
    if (r.toLowerCase().startsWith('@css:')) return RuleMode.css;
    if (r.toLowerCase().startsWith('@xpath:')) return RuleMode.xpath;
    if (r.toLowerCase().startsWith('@json:')) return RuleMode.json;
    if (r.toLowerCase().startsWith('@js:') || RegExp(r'^<js>[\s\S]*</js>$').hasMatch(r)) return RuleMode.js;
    if (r.startsWith(r'$.') || r.startsWith(r'$[')) return RuleMode.json;
    if (r.startsWith('//') || r.startsWith('/')) return RuleMode.xpath;
    if (r.startsWith(':') && RegExp(r'^:.+[\+\*\[\]\(\)\^\$]').hasMatch(r)) return RuleMode.regex;
    if (forceJson) return RuleMode.json;
    return RuleMode.defaultRule;
  }

  String _stripCssPrefix(String r) => r.toLowerCase().startsWith('@css:') ? r.substring(5) : r;
  String _stripXPathPrefix(String r) => r.toLowerCase().startsWith('@xpath:') ? r.substring(7) : r;
  String _stripJsonPrefix(String r) {
    final low = r.toLowerCase();
    if (low.startsWith('@json:')) return r.substring(6);
    return r;
  }

  bool _looksJson(String raw) {
    final t = raw.trim();
    return t.startsWith('{') || t.startsWith('[');
  }

  /// 按 @ 拆分默认规则步骤（忽略属性选择器 [] 与引号内的 @）
  List<String> _splitSteps(String rule) {
    final parts = <String>[];
    final sb = StringBuffer();
    var depth = 0;
    var quote = '';
    for (var i = 0; i < rule.length; i++) {
      final c = rule[i];
      if (quote.isNotEmpty) {
        sb.write(c);
        if (c == quote) quote = '';
        continue;
      }
      if (c == "'" || c == '"') { quote = c; sb.write(c); continue; }
      if (c == '[' || c == '(') depth++;
      if (c == ']' || c == ')') depth--;
      if (c == '@' && depth == 0) {
        if (sb.isNotEmpty) parts.add(sb.toString());
        sb.clear();
      } else {
        sb.write(c);
      }
    }
    if (sb.isNotEmpty) parts.add(sb.toString());
    return parts.where((p) => p.isNotEmpty).toList();
  }

  /// 找最后一个顶层 @（用于 CSS 的 getter 分离）
  int _lastTopAt(String rule) {
    var depth = 0;
    var quote = '';
    var idx = -1;
    for (var i = 0; i < rule.length; i++) {
      final c = rule[i];
      if (quote.isNotEmpty) { if (c == quote) quote = ''; continue; }
      if (c == "'" || c == '"') { quote = c; continue; }
      if (c == '[' || c == '(') depth++;
      if (c == ']' || c == ')') depth--;
      if (c == '@' && depth == 0) idx = i;
    }
    return idx;
  }

  /// 平衡组切分组合规则：返回（片段列表，组合类型）。
  /// 组合类型为第一个顶层出现的 `&&`/`||`/`%%`（忽略 [](){} 与引号内部），
  /// 后续出现的其他组合分隔符按普通字符处理（对齐原版「首个分隔符决定组合方式」）。
  /// 正确处理 jsonPath 谓词 `$.a[?(@.b && @.c)]`、CSS `[attr=val]`、XPath 谓词内的分隔符。
  _CombinedRule _splitCombined(String input) {
    final segments = <String>[];
    var type = '';
    final sb = StringBuffer();
    var depth = 0;
    var quote = '';
    var i = 0;
    while (i < input.length) {
      final c = input[i];
      if (quote.isNotEmpty) {
        sb.write(c);
        if (c == '\\' && i + 1 < input.length) {
          sb.write(input[i + 1]);
          i += 2;
          continue;
        }
        if (c == quote) quote = '';
        i++;
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
        sb.write(c);
        i++;
        continue;
      }
      if (c == '[' || c == '(' || c == '{') depth++;
      if (c == ']' || c == ')' || c == '}') depth--;
      if (depth == 0 && i + 1 < input.length) {
        final two = input.substring(i, i + 2);
        if ((two == '&&' || two == '||' || two == '%%') &&
            (type.isEmpty || type == two)) {
          type = two;
          segments.add(sb.toString());
          sb.clear();
          i += 2;
          continue;
        }
      }
      sb.write(c);
      i++;
    }
    segments.add(sb.toString());
    return _CombinedRule(segments, type);
  }

  /// 顶层分隔（忽略 [](){} 与引号内部），返回各段
  List<String> _splitTop(String input, List<String> seps) {
    final result = <String>[];
    final sb = StringBuffer();
    var depth = 0;
    var quote = '';
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (quote.isNotEmpty) { sb.write(c); if (c == quote) quote = ''; continue; }
      if (c == "'" || c == '"') { quote = c; sb.write(c); continue; }
      if (c == '[' || c == '(' || c == '{') depth++;
      if (c == ']' || c == ')' || c == '}') depth--;
      String? matched;
      if (depth == 0) {
        for (final s in seps) {
          if (i + s.length <= input.length && input.substring(i, i + s.length) == s) {
            matched = s; break;
          }
        }
      }
      if (matched != null) {
        result.add(sb.toString());
        sb.clear();
        i += matched.length - 1;
      } else {
        sb.write(c);
      }
    }
    if (sb.isNotEmpty) result.add(sb.toString());
    return result;
  }

  int _findTop(String input, String token) {
    var depth = 0;
    var quote = '';
    for (var i = 0; i <= input.length - token.length; i++) {
      final c = input[i];
      if (quote.isNotEmpty) { if (c == quote) quote = ''; continue; }
      if (c == "'" || c == '"') { quote = c; continue; }
      if (c == '[' || c == '(' || c == '{') depth++;
      if (c == ']' || c == ')' || c == '}') depth--;
      if (depth == 0 && input.substring(i, i + token.length) == token) return i;
    }
    return -1;
  }

  /// 按 ## 切分（顶层；不拆引号/括号内）
  List<String> _splitByHash(String input) {
    final result = <String>[];
    final sb = StringBuffer();
    var depth = 0;
    var quote = '';
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (quote.isNotEmpty) { sb.write(c); if (c == quote) quote = ''; continue; }
      if (c == "'" || c == '"') { quote = c; sb.write(c); continue; }
      if (c == '[' || c == '(' || c == '{') depth++;
      if (c == ']' || c == ')' || c == '}') depth--;
      if (depth == 0 && i + 1 < input.length && c == '#' && input[i + 1] == '#') {
        result.add(sb.toString());
        sb.clear();
        i++;
        // 三 #：###regex 保留一个前导 # 到下一段
        if (i + 1 < input.length && input[i + 1] == '#') {
          sb.write('#');
          i++;
        }
      } else {
        sb.write(c);
      }
    }
    result.add(sb.toString());
    return result;
  }

  List<String> _nullEmpty(String? s) => (s == null || s.isEmpty) ? [] : [s];

  // ============================== HTML 实体 ==============================

  /// 常用 HTML 命名实体（对齐原版 unescapeHtml4 的常用子集）
  static const Map<String, String> _htmlEntities = {
    'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", '#39': "'",
    'nbsp': ' ', 'ensp': ' ', 'emsp': ' ', 'thinsp': ' ', 'shy': '',
    'hellip': '…', 'mdash': '—', 'ndash': '–', 'middot': '·',
    'ldquo': '"', 'rdquo': '"', 'lsquo': "'", 'rsquo': "'", 'sbquo': '‚', 'bdquo': '„',
    'copy': '©', 'reg': '®', 'trade': '™', 'deg': '°', 'plusmn': '±',
    'times': '×', 'divide': '÷', 'laquo': '«', 'raquo': '»',
    'larr': '←', 'uarr': '↑', 'rarr': '→', 'darr': '↓', 'bull': '•',
    'sect': '§', 'para': '¶', 'frac12': '½', 'frac14': '¼', 'frac34': '¾',
  };

  /// HTML entity 反转义：字段取值后统一调用，避免书名/作者/简介出现 &amp; 等未解码字符。
  static String unescapeHtml(String s) {
    if (!s.contains('&')) return s;
    return s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
      final e = m.group(1)!;
      if (e.startsWith('#x') || e.startsWith('#X')) {
        return String.fromCharCode(int.tryParse(e.substring(2), radix: 16) ?? 0x3F);
      }
      if (e.startsWith('#')) {
        return String.fromCharCode(int.tryParse(e.substring(1)) ?? 0x3F);
      }
      return _htmlEntities[e] ?? m.group(0)!;
    });
  }
}

/// 组合规则切分结果
class _CombinedRule {
  _CombinedRule(this.segments, this.type);
  final List<String> segments;
  final String type; // '' / '&&' / '||' / '%%'
}

/// 元素索引解析结果
class _IndexResult {
  _IndexResult(this.before, this.exclude, this.entries);
  final String before; // 索引前的选择器部分
  final bool exclude; // 是否排除（! 前缀）
  final List<dynamic> entries; // int（单索引）或 (int?,int?,int)（区间 start/end/step）
}

class _ParsedRule {
  String selector = '';
  final List<_PostOp> ops = [];
  String? tailJs;
  bool hasInterpolation = false;
}

/// 字段规则拆解结果（供异步 JS 引擎使用）。
class FieldRuleParts {
  FieldRuleParts({
    required this.selector,
    required this.ops,
    this.tailJs,
    this.hasInterpolation = false,
  });
  String selector;
  final List<FieldOp> ops;
  String? tailJs;
  bool hasInterpolation;
}

class FieldOp {
  FieldOp(this.kind, this.pattern, this.replacement);
  final String kind; // remove / replace / match
  final String pattern;
  final String? replacement;
}

enum _OpKind { remove, replace, match }

class _PostOp {
  final _OpKind kind;
  final String pattern;
  final String? replacement;
  _PostOp._(this.kind, this.pattern, this.replacement);
  factory _PostOp.remove(String p) => _PostOp._(_OpKind.remove, p, null);
  factory _PostOp.replace(String p, String r) => _PostOp._(_OpKind.replace, p, r);
  factory _PostOp.match(String p) => _PostOp._(_OpKind.match, p, null);
}
