import 'package:flutter/material.dart';
import '../../data/model/rss_source.dart';
import 'package:legado_md3/data/local/app_database.dart';

/// RSS源编辑页面 - 对齐原版RssSourceEditScreen(4 Tab)
class RssSourceEditScreen extends StatefulWidget {
  final RssSource? source;
  const RssSourceEditScreen({super.key, this.source});

  @override
  State<RssSourceEditScreen> createState() => _RssSourceEditScreenState();
}

class _RssSourceEditScreenState extends State<RssSourceEditScreen> with SingleTickerProviderStateMixin {
  final _db = DatabaseService();
  late TabController _tabController;
  late RssSource _s;

  // Base
  late final TextEditingController _name, _url, _icon, _group, _comment;
  late final TextEditingController _searchUrl, _sortUrl, _loginUrl, _loginUi, _loginCheckJs;
  late final TextEditingController _coverDecodeJs, _header, _variableComment, _concurrentRate, _jsLib;
  // Start
  late final TextEditingController _startHtml, _startStyle, _startJs, _preloadJs;
  // List
  late final TextEditingController _ruleArticles, _ruleNextPage, _ruleTitle, _rulePubDate;
  late final TextEditingController _ruleDescription, _ruleImage, _ruleLink;
  // WebView
  late final TextEditingController _ruleContent, _style, _injectJs, _whitelist, _blacklist, _urlIntercept;

  @override
  void initState() {
    super.initState();
    _s = widget.source ?? RssSource();
    _tabController = TabController(length: 4, vsync: this);
    _name = TextEditingController(text: _s.sourceName);
    _url = TextEditingController(text: _s.sourceUrl);
    _icon = TextEditingController(text: _s.sourceIcon ?? '');
    _group = TextEditingController(text: _s.sourceGroup ?? '');
    _comment = TextEditingController(text: _s.sourceComment ?? '');
    _searchUrl = TextEditingController(text: _s.searchUrl ?? '');
    _sortUrl = TextEditingController(text: _s.sortUrl ?? '');
    _loginUrl = TextEditingController(text: _s.loginUrl ?? '');
    _loginUi = TextEditingController(text: _s.loginUi ?? '');
    _loginCheckJs = TextEditingController(text: _s.loginCheckJs ?? '');
    _coverDecodeJs = TextEditingController(text: _s.coverDecodeJs ?? '');
    _header = TextEditingController(text: _s.header ?? '');
    _variableComment = TextEditingController(text: _s.variableComment ?? '');
    _concurrentRate = TextEditingController(text: _s.concurrentRate ?? '');
    _jsLib = TextEditingController(text: _s.jsLib ?? '');
    _startHtml = TextEditingController(text: _s.startHtml ?? '');
    _startStyle = TextEditingController(text: _s.startStyle ?? '');
    _startJs = TextEditingController(text: _s.startJs ?? '');
    _preloadJs = TextEditingController(text: _s.preloadJs ?? '');
    _ruleArticles = TextEditingController(text: _s.ruleArticles ?? '');
    _ruleNextPage = TextEditingController(text: _s.ruleNextPage ?? '');
    _ruleTitle = TextEditingController(text: _s.ruleTitle ?? '');
    _rulePubDate = TextEditingController(text: _s.rulePubDate ?? '');
    _ruleDescription = TextEditingController(text: _s.ruleDescription ?? '');
    _ruleImage = TextEditingController(text: _s.ruleImage ?? '');
    _ruleLink = TextEditingController(text: _s.ruleLink ?? '');
    _ruleContent = TextEditingController(text: _s.ruleContent ?? '');
    _style = TextEditingController(text: _s.style ?? '');
    _injectJs = TextEditingController(text: _s.injectJs ?? '');
    _whitelist = TextEditingController(text: _s.contentWhitelist ?? '');
    _blacklist = TextEditingController(text: _s.contentBlacklist ?? '');
    _urlIntercept = TextEditingController(text: _s.shouldOverrideUrlLoading ?? '');
  }

  Widget _field(TextEditingController c, String label, {int lines = 1, String? hint}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(controller: c, maxLines: lines, decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), alignLabelWithHint: lines > 1)),
  );

  Future<void> _save() async {
    _s
      ..sourceName = _name.text
      ..sourceUrl = _url.text
      ..sourceIcon = _icon.text
      ..sourceGroup = _group.text
      ..sourceComment = _comment.text
      ..searchUrl = _searchUrl.text
      ..sortUrl = _sortUrl.text
      ..loginUrl = _loginUrl.text
      ..loginUi = _loginUi.text
      ..loginCheckJs = _loginCheckJs.text
      ..coverDecodeJs = _coverDecodeJs.text
      ..header = _header.text
      ..variableComment = _variableComment.text
      ..concurrentRate = _concurrentRate.text
      ..jsLib = _jsLib.text
      ..startHtml = _startHtml.text
      ..startStyle = _startStyle.text
      ..startJs = _startJs.text
      ..preloadJs = _preloadJs.text
      ..ruleArticles = _ruleArticles.text
      ..ruleNextPage = _ruleNextPage.text
      ..ruleTitle = _ruleTitle.text
      ..rulePubDate = _rulePubDate.text
      ..ruleDescription = _ruleDescription.text
      ..ruleImage = _ruleImage.text
      ..ruleLink = _ruleLink.text
      ..ruleContent = _ruleContent.text
      ..style = _style.text
      ..injectJs = _injectJs.text
      ..contentWhitelist = _whitelist.text
      ..contentBlacklist = _blacklist.text
      ..shouldOverrideUrlLoading = _urlIntercept.text;
    if (widget.source == null) {
      await _db.insertRssSource(_s);
    } else {
      await _db.updateRssSource(_s);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.source == null ? '新建RSS源' : '编辑RSS源'),
        actions: [IconButton(icon: const Icon(Icons.save), onPressed: _save)],
        bottom: TabBar(controller: _tabController, isScrollable: true, tabs: const [
          Tab(text: '基本'), Tab(text: '起始'), Tab(text: '列表'), Tab(text: 'WebView'),
        ]),
      ),
      body: TabBarView(controller: _tabController, children: [
        // Base Tab
        SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
          _field(_name, '源名称'),
          _field(_url, '源URL'),
          _field(_icon, '源图标'),
          _field(_group, '源分组'),
          _field(_comment, '注释', lines: 2),
          _field(_searchUrl, '搜索URL'),
          _field(_sortUrl, '排序URL'),
          _field(_loginUrl, '登录URL'),
          _field(_loginUi, '登录UI', lines: 3),
          _field(_loginCheckJs, '登录检查JS', lines: 3),
          _field(_coverDecodeJs, '封面解码JS', lines: 3),
          _field(_header, 'HTTP请求头', lines: 3),
          _field(_variableComment, '变量注释', lines: 2),
          _field(_concurrentRate, '并发率'),
          _field(_jsLib, 'jsLib', lines: 3),
        ])),
        // Start Tab
        SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
          _field(_startHtml, 'startHtml', lines: 3),
          _field(_startStyle, 'startStyle', lines: 3),
          _field(_startJs, 'startJs', lines: 3),
          _field(_preloadJs, 'preloadJs', lines: 3),
        ])),
        // List Tab
        SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
          _field(_ruleArticles, '文章列表规则', lines: 2),
          _field(_ruleNextPage, '下一页规则'),
          _field(_ruleTitle, '标题规则'),
          _field(_rulePubDate, '发布日期规则'),
          _field(_ruleDescription, '描述规则', lines: 2),
          _field(_ruleImage, '图片规则'),
          _field(_ruleLink, '链接规则'),
        ])),
        // WebView Tab
        SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
          _field(_ruleContent, '正文规则', lines: 3),
          _field(_style, '样式', lines: 3),
          _field(_injectJs, '注入JS', lines: 3),
          _field(_whitelist, '内容白名单', lines: 2),
          _field(_blacklist, '内容黑名单', lines: 2),
          _field(_urlIntercept, 'URL跳转拦截JS', lines: 2),
        ])),
      ]),
    );
  }
}
