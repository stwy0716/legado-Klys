import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/ui/book/source/source_debug_screen.dart';

class SourceEditScreen extends StatefulWidget {
  final BookSource? source;
  const SourceEditScreen({super.key, this.source});

  @override
  State<SourceEditScreen> createState() => _SourceEditScreenState();
}

class _SourceEditScreenState extends State<SourceEditScreen> with SingleTickerProviderStateMixin {
  final DatabaseService _db = DatabaseService();
  late TabController _tabController;

  // 基础信息
  late TextEditingController _bookSourceUrl;
  late TextEditingController _bookSourceName;
  late TextEditingController _bookSourceGroup;
  late TextEditingController _bookSourceComment;
  late TextEditingController _loginUrl;
  late TextEditingController _loginUi;
  late TextEditingController _loginCheckJs;
  late TextEditingController _coverDecodeJs;
  late TextEditingController _bookUrlPattern;
  late TextEditingController _header;
  late TextEditingController _variableComment;
  late TextEditingController _jsLib;

  // 搜索
  late TextEditingController _searchUrl;
  late TextEditingController _checkKeyWord;
  late TextEditingController _searchBookList;
  late TextEditingController _searchName;
  late TextEditingController _searchAuthor;
  late TextEditingController _searchKind;
  late TextEditingController _searchWordCount;
  late TextEditingController _searchLastChapter;
  late TextEditingController _searchIntro;
  late TextEditingController _searchCoverUrl;
  late TextEditingController _searchBookUrl;

  // 发现
  late TextEditingController _exploreUrl;
  late TextEditingController _exploreBookList;
  late TextEditingController _exploreName;
  late TextEditingController _exploreAuthor;
  late TextEditingController _exploreKind;
  late TextEditingController _exploreWordCount;
  late TextEditingController _exploreLastChapter;
  late TextEditingController _exploreIntro;
  late TextEditingController _exploreCoverUrl;
  late TextEditingController _exploreBookUrl;
  late TextEditingController _homepageModules;

  // 详情
  late TextEditingController _infoInit;
  late TextEditingController _infoName;
  late TextEditingController _infoAuthor;
  late TextEditingController _infoKind;
  late TextEditingController _infoWordCount;
  late TextEditingController _infoLastChapter;
  late TextEditingController _infoIntro;
  late TextEditingController _infoCoverUrl;
  late TextEditingController _infoTocUrl;
  late TextEditingController _infoCanReName;
  late TextEditingController _infoDownloadUrls;
  late TextEditingController _infoRelatedBooks;

  // 目录
  late TextEditingController _tocPreUpdateJs;
  late TextEditingController _tocChapterList;
  late TextEditingController _tocChapterName;
  late TextEditingController _tocChapterUrl;
  late TextEditingController _tocFormatJs;
  late TextEditingController _tocIsVolume;
  late TextEditingController _tocUpdateTime;
  late TextEditingController _tocIsVip;
  late TextEditingController _tocIsPay;
  late TextEditingController _tocNextTocUrl;

  // 正文
  late TextEditingController _contentContent;
  late TextEditingController _contentSubContent;
  late TextEditingController _contentTitle;
  late TextEditingController _contentNextContentUrl;
  late TextEditingController _contentWebJs;
  late TextEditingController _contentSourceRegex;
  late TextEditingController _contentReplaceRegex;
  late TextEditingController _contentImageStyle;
  late TextEditingController _contentImageDecode;
  late TextEditingController _contentPayAction;
  late TextEditingController _contentCallBackJs;

  bool _enabled = true;
  bool _enabledExplore = false;
  bool _eventListener = false;
  bool _customButton = false;
  int _bookSourceType = 0;

  static const List<String> _tabs = ['基础', '搜索', '发现', '详情', '目录', '正文'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _initControllers();
    _loadFromSource();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _disposeAll();
    super.dispose();
  }

  void _initControllers() {
    _bookSourceUrl = TextEditingController();
    _bookSourceName = TextEditingController();
    _bookSourceGroup = TextEditingController();
    _bookSourceComment = TextEditingController();
    _loginUrl = TextEditingController();
    _loginUi = TextEditingController();
    _loginCheckJs = TextEditingController();
    _coverDecodeJs = TextEditingController();
    _bookUrlPattern = TextEditingController();
    _header = TextEditingController();
    _variableComment = TextEditingController();
    _jsLib = TextEditingController();
    _searchUrl = TextEditingController();
    _checkKeyWord = TextEditingController();
    _searchBookList = TextEditingController();
    _searchName = TextEditingController();
    _searchAuthor = TextEditingController();
    _searchKind = TextEditingController();
    _searchWordCount = TextEditingController();
    _searchLastChapter = TextEditingController();
    _searchIntro = TextEditingController();
    _searchCoverUrl = TextEditingController();
    _searchBookUrl = TextEditingController();
    _exploreUrl = TextEditingController();
    _exploreBookList = TextEditingController();
    _exploreName = TextEditingController();
    _exploreAuthor = TextEditingController();
    _exploreKind = TextEditingController();
    _exploreWordCount = TextEditingController();
    _exploreLastChapter = TextEditingController();
    _exploreIntro = TextEditingController();
    _exploreCoverUrl = TextEditingController();
    _exploreBookUrl = TextEditingController();
    _homepageModules = TextEditingController();
    _infoInit = TextEditingController();
    _infoName = TextEditingController();
    _infoAuthor = TextEditingController();
    _infoKind = TextEditingController();
    _infoWordCount = TextEditingController();
    _infoLastChapter = TextEditingController();
    _infoIntro = TextEditingController();
    _infoCoverUrl = TextEditingController();
    _infoTocUrl = TextEditingController();
    _infoCanReName = TextEditingController();
    _infoDownloadUrls = TextEditingController();
    _infoRelatedBooks = TextEditingController();
    _tocPreUpdateJs = TextEditingController();
    _tocChapterList = TextEditingController();
    _tocChapterName = TextEditingController();
    _tocChapterUrl = TextEditingController();
    _tocFormatJs = TextEditingController();
    _tocIsVolume = TextEditingController();
    _tocUpdateTime = TextEditingController();
    _tocIsVip = TextEditingController();
    _tocIsPay = TextEditingController();
    _tocNextTocUrl = TextEditingController();
    _contentContent = TextEditingController();
    _contentSubContent = TextEditingController();
    _contentTitle = TextEditingController();
    _contentNextContentUrl = TextEditingController();
    _contentWebJs = TextEditingController();
    _contentSourceRegex = TextEditingController();
    _contentReplaceRegex = TextEditingController();
    _contentImageStyle = TextEditingController();
    _contentImageDecode = TextEditingController();
    _contentPayAction = TextEditingController();
    _contentCallBackJs = TextEditingController();
  }

  void _disposeAll() {
    for (final c in [
      _bookSourceUrl, _bookSourceName, _bookSourceGroup, _bookSourceComment,
      _loginUrl, _loginUi, _loginCheckJs, _coverDecodeJs, _bookUrlPattern, _header, _variableComment, _jsLib,
      _searchUrl, _checkKeyWord, _searchBookList, _searchName, _searchAuthor, _searchKind,
      _searchWordCount, _searchLastChapter, _searchIntro, _searchCoverUrl, _searchBookUrl,
      _exploreUrl, _exploreBookList, _exploreName, _exploreAuthor, _exploreKind,
      _exploreWordCount, _exploreLastChapter, _exploreIntro, _exploreCoverUrl, _exploreBookUrl, _homepageModules,
      _infoInit, _infoName, _infoAuthor, _infoKind, _infoWordCount, _infoLastChapter,
      _infoIntro, _infoCoverUrl, _infoTocUrl, _infoCanReName, _infoDownloadUrls, _infoRelatedBooks,
      _tocPreUpdateJs, _tocChapterList, _tocChapterName, _tocChapterUrl, _tocFormatJs,
      _tocIsVolume, _tocUpdateTime, _tocIsVip, _tocIsPay, _tocNextTocUrl,
      _contentContent, _contentSubContent, _contentTitle, _contentNextContentUrl, _contentWebJs,
      _contentSourceRegex, _contentReplaceRegex, _contentImageStyle, _contentImageDecode,
      _contentPayAction, _contentCallBackJs,
    ]) {
      c.dispose();
    }
  }

  String _ruleValue(Map<String, dynamic>? rule, String key) => rule?[key]?.toString() ?? '';

  void _loadFromSource() {
    final s = widget.source;
    if (s == null) return;
    _bookSourceUrl.text = s.bookSourceUrl;
    _bookSourceName.text = s.bookSourceName;
    _bookSourceGroup.text = s.bookSourceGroup ?? '';
    _bookSourceComment.text = s.bookSourceComment ?? '';
    _loginUrl.text = s.loginUrl ?? '';
    _loginUi.text = s.loginUi ?? '';
    _loginCheckJs.text = s.loginCheckJs ?? '';
    _coverDecodeJs.text = s.coverDecodeJs ?? '';
    _bookUrlPattern.text = s.bookUrlPattern ?? '';
    _header.text = s.header ?? '';
    _variableComment.text = s.variableComment ?? '';
    _jsLib.text = s.jsLib ?? '';
    _enabled = s.enabled;
    _enabledExplore = s.enabledExplore;
    _eventListener = s.eventListener;
    _customButton = s.customButton;
    _bookSourceType = s.bookSourceType;

    final rs = s.ruleSearch ?? {};
    _searchUrl.text = s.searchUrl ?? '';
    _checkKeyWord.text = _ruleValue(rs, 'checkKeyWord');
    _searchBookList.text = _ruleValue(rs, 'bookList');
    _searchName.text = _ruleValue(rs, 'name');
    _searchAuthor.text = _ruleValue(rs, 'author');
    _searchKind.text = _ruleValue(rs, 'kind');
    _searchWordCount.text = _ruleValue(rs, 'wordCount');
    _searchLastChapter.text = _ruleValue(rs, 'lastChapter');
    _searchIntro.text = _ruleValue(rs, 'intro');
    _searchCoverUrl.text = _ruleValue(rs, 'coverUrl');
    _searchBookUrl.text = _ruleValue(rs, 'bookUrl');

    final re = s.ruleExplore ?? {};
    _exploreUrl.text = s.exploreUrl ?? '';
    _exploreBookList.text = _ruleValue(re, 'bookList');
    _exploreName.text = _ruleValue(re, 'name');
    _exploreAuthor.text = _ruleValue(re, 'author');
    _exploreKind.text = _ruleValue(re, 'kind');
    _exploreWordCount.text = _ruleValue(re, 'wordCount');
    _exploreLastChapter.text = _ruleValue(re, 'lastChapter');
    _exploreIntro.text = _ruleValue(re, 'intro');
    _exploreCoverUrl.text = _ruleValue(re, 'coverUrl');
    _exploreBookUrl.text = _ruleValue(re, 'bookUrl');
    _homepageModules.text = s.homepageModules ?? '';

    final ri = s.ruleBookInfo ?? {};
    _infoInit.text = _ruleValue(ri, 'init');
    _infoName.text = _ruleValue(ri, 'name');
    _infoAuthor.text = _ruleValue(ri, 'author');
    _infoKind.text = _ruleValue(ri, 'kind');
    _infoWordCount.text = _ruleValue(ri, 'wordCount');
    _infoLastChapter.text = _ruleValue(ri, 'lastChapter');
    _infoIntro.text = _ruleValue(ri, 'intro');
    _infoCoverUrl.text = _ruleValue(ri, 'coverUrl');
    _infoTocUrl.text = _ruleValue(ri, 'tocUrl');
    _infoCanReName.text = _ruleValue(ri, 'canReName');
    _infoDownloadUrls.text = _ruleValue(ri, 'downloadUrls');
    _infoRelatedBooks.text = _ruleValue(ri, 'relatedBooks');

    final rt = s.ruleToc ?? {};
    _tocPreUpdateJs.text = _ruleValue(rt, 'preUpdateJs');
    _tocChapterList.text = _ruleValue(rt, 'chapterList');
    _tocChapterName.text = _ruleValue(rt, 'chapterName');
    _tocChapterUrl.text = _ruleValue(rt, 'chapterUrl');
    _tocFormatJs.text = _ruleValue(rt, 'formatJs');
    _tocIsVolume.text = _ruleValue(rt, 'isVolume');
    _tocUpdateTime.text = _ruleValue(rt, 'updateTime');
    _tocIsVip.text = _ruleValue(rt, 'isVip');
    _tocIsPay.text = _ruleValue(rt, 'isPay');
    _tocNextTocUrl.text = _ruleValue(rt, 'nextTocUrl');

    final rc = s.ruleContent ?? {};
    _contentContent.text = _ruleValue(rc, 'content');
    _contentSubContent.text = _ruleValue(rc, 'subContent');
    _contentTitle.text = _ruleValue(rc, 'title');
    _contentNextContentUrl.text = _ruleValue(rc, 'nextContentUrl');
    _contentWebJs.text = _ruleValue(rc, 'webJs');
    _contentSourceRegex.text = _ruleValue(rc, 'sourceRegex');
    _contentReplaceRegex.text = _ruleValue(rc, 'replaceRegex');
    _contentImageStyle.text = _ruleValue(rc, 'imageStyle');
    _contentImageDecode.text = _ruleValue(rc, 'imageDecode');
    _contentPayAction.text = _ruleValue(rc, 'payAction');
    _contentCallBackJs.text = _ruleValue(rc, 'callBackJs');
  }

  Map<String, dynamic>? _buildRule(Map<TextEditingController, String> fields) {
    final map = <String, dynamic>{};
    fields.forEach((controller, key) {
      if (controller.text.isNotEmpty) map[key] = controller.text;
    });
    return map.isEmpty ? null : map;
  }

  Future<void> _saveSource() async {
    if (_bookSourceUrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('书源URL不能为空')));
      return;
    }
    if (_bookSourceName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('书源名称不能为空')));
      return;
    }

    final source = BookSource(
      bookSourceUrl: _bookSourceUrl.text.trim(),
      bookSourceName: _bookSourceName.text.trim(),
      bookSourceGroup: _bookSourceGroup.text.trim().isEmpty ? null : _bookSourceGroup.text.trim(),
      bookSourceType: _bookSourceType,
      bookSourceComment: _bookSourceComment.text.trim().isEmpty ? null : _bookSourceComment.text.trim(),
      enabled: _enabled,
      enabledExplore: _enabledExplore,
      loginUrl: _loginUrl.text.trim().isEmpty ? null : _loginUrl.text.trim(),
      loginUi: _loginUi.text.trim().isEmpty ? null : _loginUi.text.trim(),
      loginCheckJs: _loginCheckJs.text.trim().isEmpty ? null : _loginCheckJs.text.trim(),
      coverDecodeJs: _coverDecodeJs.text.trim().isEmpty ? null : _coverDecodeJs.text.trim(),
      bookUrlPattern: _bookUrlPattern.text.trim().isEmpty ? null : _bookUrlPattern.text.trim(),
      header: _header.text.trim().isEmpty ? null : _header.text.trim(),
      variableComment: _variableComment.text.trim().isEmpty ? null : _variableComment.text.trim(),
      jsLib: _jsLib.text.trim().isEmpty ? null : _jsLib.text.trim(),
      searchUrl: _searchUrl.text.trim().isEmpty ? null : _searchUrl.text.trim(),
      exploreUrl: _exploreUrl.text.trim().isEmpty ? null : _exploreUrl.text.trim(),
      exploreScreen: null,
      checkKeyWord: _checkKeyWord.text.trim().isEmpty ? null : _checkKeyWord.text.trim(),
      ruleSearch: _buildRule({
        _checkKeyWord: 'checkKeyWord', _searchBookList: 'bookList', _searchName: 'name',
        _searchAuthor: 'author', _searchKind: 'kind', _searchWordCount: 'wordCount',
        _searchLastChapter: 'lastChapter', _searchIntro: 'intro', _searchCoverUrl: 'coverUrl', _searchBookUrl: 'bookUrl',
      }),
      ruleExplore: _buildRule({
        _exploreBookList: 'bookList', _exploreName: 'name', _exploreAuthor: 'author',
        _exploreKind: 'kind', _exploreWordCount: 'wordCount', _exploreLastChapter: 'lastChapter',
        _exploreIntro: 'intro', _exploreCoverUrl: 'coverUrl', _exploreBookUrl: 'bookUrl',
      }),
      ruleBookInfo: _buildRule({
        _infoInit: 'init', _infoName: 'name', _infoAuthor: 'author', _infoKind: 'kind',
        _infoWordCount: 'wordCount', _infoLastChapter: 'lastChapter', _infoIntro: 'intro',
        _infoCoverUrl: 'coverUrl', _infoTocUrl: 'tocUrl', _infoCanReName: 'canReName',
        _infoDownloadUrls: 'downloadUrls', _infoRelatedBooks: 'relatedBooks',
      }),
      ruleToc: _buildRule({
        _tocPreUpdateJs: 'preUpdateJs', _tocChapterList: 'chapterList', _tocChapterName: 'chapterName',
        _tocChapterUrl: 'chapterUrl', _tocFormatJs: 'formatJs', _tocIsVolume: 'isVolume',
        _tocUpdateTime: 'updateTime', _tocIsVip: 'isVip', _tocIsPay: 'isPay', _tocNextTocUrl: 'nextTocUrl',
      }),
      ruleContent: _buildRule({
        _contentContent: 'content', _contentSubContent: 'subContent', _contentTitle: 'title',
        _contentNextContentUrl: 'nextContentUrl', _contentWebJs: 'webJs',
        _contentSourceRegex: 'sourceRegex', _contentReplaceRegex: 'replaceRegex',
        _contentImageStyle: 'imageStyle', _contentImageDecode: 'imageDecode',
        _contentPayAction: 'payAction', _contentCallBackJs: 'callBackJs',
      }),
      ruleReview: null,
      ruleImage: null,
      variable: null,
      customOrder: widget.source?.customOrder ?? 0,
      respondTime: widget.source?.respondTime ?? 180000,
      weight: widget.source?.weight ?? 0,
      lastUpdateTime: DateTime.now().millisecondsSinceEpoch,
      eventListener: _eventListener,
      customButton: _customButton,
      homepageModules: _homepageModules.text.trim().isEmpty ? null : _homepageModules.text.trim(),
    );

    try {
      final existing = await _db.getSource(source.bookSourceUrl);
      if (existing != null) {
        await _db.updateSource(source);
      } else {
        await _db.insertSource(source);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存成功')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
  }

  Future<void> _copySource() async {
    final source = await _buildSourceForExport();
    await Clipboard.setData(ClipboardData(text: jsonEncode(source.toJson())));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
  }

  Future<void> _pasteSource() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null || data.text == null || data.text!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('剪贴板为空')));
      return;
    }
    try {
      final json = jsonDecode(data.text!);
      if (json is Map<String, dynamic>) {
        final source = BookSource.fromJson(json);
        setState(() {
          widget.source != null ? _loadFromExisting(source) : null;
        });
        // 直接加载到表单
        _loadFromSourceObject(source);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已粘贴书源')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('粘贴失败: $e')));
    }
  }

  void _loadFromSourceObject(BookSource s) {
    _bookSourceUrl.text = s.bookSourceUrl;
    _bookSourceName.text = s.bookSourceName;
    _bookSourceGroup.text = s.bookSourceGroup ?? '';
    _bookSourceComment.text = s.bookSourceComment ?? '';
    _loginUrl.text = s.loginUrl ?? '';
    _loginUi.text = s.loginUi ?? '';
    _loginCheckJs.text = s.loginCheckJs ?? '';
    _coverDecodeJs.text = s.coverDecodeJs ?? '';
    _bookUrlPattern.text = s.bookUrlPattern ?? '';
    _header.text = s.header ?? '';
    _variableComment.text = s.variableComment ?? '';
    _jsLib.text = s.jsLib ?? '';
    _enabled = s.enabled;
    _enabledExplore = s.enabledExplore;
    _eventListener = s.eventListener;
    _customButton = s.customButton;
    _bookSourceType = s.bookSourceType;
    _searchUrl.text = s.searchUrl ?? '';
    _exploreUrl.text = s.exploreUrl ?? '';
    _homepageModules.text = s.homepageModules ?? '';

    final rs = s.ruleSearch ?? {};
    _checkKeyWord.text = _ruleValue(rs, 'checkKeyWord');
    _searchBookList.text = _ruleValue(rs, 'bookList');
    _searchName.text = _ruleValue(rs, 'name');
    _searchAuthor.text = _ruleValue(rs, 'author');
    _searchKind.text = _ruleValue(rs, 'kind');
    _searchWordCount.text = _ruleValue(rs, 'wordCount');
    _searchLastChapter.text = _ruleValue(rs, 'lastChapter');
    _searchIntro.text = _ruleValue(rs, 'intro');
    _searchCoverUrl.text = _ruleValue(rs, 'coverUrl');
    _searchBookUrl.text = _ruleValue(rs, 'bookUrl');

    final re = s.ruleExplore ?? {};
    _exploreBookList.text = _ruleValue(re, 'bookList');
    _exploreName.text = _ruleValue(re, 'name');
    _exploreAuthor.text = _ruleValue(re, 'author');
    _exploreKind.text = _ruleValue(re, 'kind');
    _exploreWordCount.text = _ruleValue(re, 'wordCount');
    _exploreLastChapter.text = _ruleValue(re, 'lastChapter');
    _exploreIntro.text = _ruleValue(re, 'intro');
    _exploreCoverUrl.text = _ruleValue(re, 'coverUrl');
    _exploreBookUrl.text = _ruleValue(re, 'bookUrl');

    final ri = s.ruleBookInfo ?? {};
    _infoInit.text = _ruleValue(ri, 'init');
    _infoName.text = _ruleValue(ri, 'name');
    _infoAuthor.text = _ruleValue(ri, 'author');
    _infoKind.text = _ruleValue(ri, 'kind');
    _infoWordCount.text = _ruleValue(ri, 'wordCount');
    _infoLastChapter.text = _ruleValue(ri, 'lastChapter');
    _infoIntro.text = _ruleValue(ri, 'intro');
    _infoCoverUrl.text = _ruleValue(ri, 'coverUrl');
    _infoTocUrl.text = _ruleValue(ri, 'tocUrl');
    _infoCanReName.text = _ruleValue(ri, 'canReName');
    _infoDownloadUrls.text = _ruleValue(ri, 'downloadUrls');
    _infoRelatedBooks.text = _ruleValue(ri, 'relatedBooks');

    final rt = s.ruleToc ?? {};
    _tocPreUpdateJs.text = _ruleValue(rt, 'preUpdateJs');
    _tocChapterList.text = _ruleValue(rt, 'chapterList');
    _tocChapterName.text = _ruleValue(rt, 'chapterName');
    _tocChapterUrl.text = _ruleValue(rt, 'chapterUrl');
    _tocFormatJs.text = _ruleValue(rt, 'formatJs');
    _tocIsVolume.text = _ruleValue(rt, 'isVolume');
    _tocUpdateTime.text = _ruleValue(rt, 'updateTime');
    _tocIsVip.text = _ruleValue(rt, 'isVip');
    _tocIsPay.text = _ruleValue(rt, 'isPay');
    _tocNextTocUrl.text = _ruleValue(rt, 'nextTocUrl');

    final rc = s.ruleContent ?? {};
    _contentContent.text = _ruleValue(rc, 'content');
    _contentSubContent.text = _ruleValue(rc, 'subContent');
    _contentTitle.text = _ruleValue(rc, 'title');
    _contentNextContentUrl.text = _ruleValue(rc, 'nextContentUrl');
    _contentWebJs.text = _ruleValue(rc, 'webJs');
    _contentSourceRegex.text = _ruleValue(rc, 'sourceRegex');
    _contentReplaceRegex.text = _ruleValue(rc, 'replaceRegex');
    _contentImageStyle.text = _ruleValue(rc, 'imageStyle');
    _contentImageDecode.text = _ruleValue(rc, 'imageDecode');
    _contentPayAction.text = _ruleValue(rc, 'payAction');
    _contentCallBackJs.text = _ruleValue(rc, 'callBackJs');

    setState(() {});
  }

  void _loadFromExisting(BookSource s) {}

  Future<BookSource> _buildSourceForExport() async {
    return BookSource(
      bookSourceUrl: _bookSourceUrl.text.trim(),
      bookSourceName: _bookSourceName.text.trim(),
      bookSourceGroup: _bookSourceGroup.text.trim().isEmpty ? null : _bookSourceGroup.text.trim(),
      bookSourceType: _bookSourceType,
      bookSourceComment: _bookSourceComment.text.trim().isEmpty ? null : _bookSourceComment.text.trim(),
      enabled: _enabled,
      enabledExplore: _enabledExplore,
      loginUrl: _loginUrl.text.trim().isEmpty ? null : _loginUrl.text.trim(),
      loginUi: _loginUi.text.trim().isEmpty ? null : _loginUi.text.trim(),
      loginCheckJs: _loginCheckJs.text.trim().isEmpty ? null : _loginCheckJs.text.trim(),
      coverDecodeJs: _coverDecodeJs.text.trim().isEmpty ? null : _coverDecodeJs.text.trim(),
      bookUrlPattern: _bookUrlPattern.text.trim().isEmpty ? null : _bookUrlPattern.text.trim(),
      header: _header.text.trim().isEmpty ? null : _header.text.trim(),
      variableComment: _variableComment.text.trim().isEmpty ? null : _variableComment.text.trim(),
      jsLib: _jsLib.text.trim().isEmpty ? null : _jsLib.text.trim(),
      searchUrl: _searchUrl.text.trim().isEmpty ? null : _searchUrl.text.trim(),
      exploreUrl: _exploreUrl.text.trim().isEmpty ? null : _exploreUrl.text.trim(),
      ruleSearch: _buildRule({
        _checkKeyWord: 'checkKeyWord', _searchBookList: 'bookList', _searchName: 'name',
        _searchAuthor: 'author', _searchKind: 'kind', _searchWordCount: 'wordCount',
        _searchLastChapter: 'lastChapter', _searchIntro: 'intro', _searchCoverUrl: 'coverUrl', _searchBookUrl: 'bookUrl',
      }),
      ruleExplore: _buildRule({
        _exploreBookList: 'bookList', _exploreName: 'name', _exploreAuthor: 'author',
        _exploreKind: 'kind', _exploreWordCount: 'wordCount', _exploreLastChapter: 'lastChapter',
        _exploreIntro: 'intro', _exploreCoverUrl: 'coverUrl', _exploreBookUrl: 'bookUrl',
      }),
      ruleBookInfo: _buildRule({
        _infoInit: 'init', _infoName: 'name', _infoAuthor: 'author', _infoKind: 'kind',
        _infoWordCount: 'wordCount', _infoLastChapter: 'lastChapter', _infoIntro: 'intro',
        _infoCoverUrl: 'coverUrl', _infoTocUrl: 'tocUrl', _infoCanReName: 'canReName',
        _infoDownloadUrls: 'downloadUrls', _infoRelatedBooks: 'relatedBooks',
      }),
      ruleToc: _buildRule({
        _tocPreUpdateJs: 'preUpdateJs', _tocChapterList: 'chapterList', _tocChapterName: 'chapterName',
        _tocChapterUrl: 'chapterUrl', _tocFormatJs: 'formatJs', _tocIsVolume: 'isVolume',
        _tocUpdateTime: 'updateTime', _tocIsVip: 'isVip', _tocIsPay: 'isPay', _tocNextTocUrl: 'nextTocUrl',
      }),
      ruleContent: _buildRule({
        _contentContent: 'content', _contentSubContent: 'subContent', _contentTitle: 'title',
        _contentNextContentUrl: 'nextContentUrl', _contentWebJs: 'webJs',
        _contentSourceRegex: 'sourceRegex', _contentReplaceRegex: 'replaceRegex',
        _contentImageStyle: 'imageStyle', _contentImageDecode: 'imageDecode',
        _contentPayAction: 'payAction', _contentCallBackJs: 'callBackJs',
      }),
      customOrder: widget.source?.customOrder ?? 0,
      respondTime: widget.source?.respondTime ?? 180000,
      weight: widget.source?.weight ?? 0,
      lastUpdateTime: DateTime.now().millisecondsSinceEpoch,
      eventListener: _eventListener,
      customButton: _customButton,
      homepageModules: _homepageModules.text.trim().isEmpty ? null : _homepageModules.text.trim(),
    );
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('调试书源'),
              onTap: () async {
                Navigator.pop(context);
                await _saveSource();
                if (mounted) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => SourceDebugScreen(source: BookSource(bookSourceUrl: _bookSourceUrl.text.trim(), bookSourceName: _bookSourceName.text.trim()))));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制书源'),
              onTap: () { Navigator.pop(context); _copySource(); },
            ),
            ListTile(
              leading: const Icon(Icons.paste),
              title: const Text('粘贴书源'),
              onTap: () { Navigator.pop(context); _pasteSource(); },
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('帮助'),
              onTap: () {
                Navigator.pop(context);
                _showHelp();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('书源规则帮助'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('CSS选择器:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('  格式: class.xxx@tag.xxx 或 #id@tag'),
              Text('  示例: .book-list@tag.li'),
              SizedBox(height: 8),
              Text('XPath:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('  格式: //div[@class="xxx"]'),
              SizedBox(height: 8),
              Text('JSONPath:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(r'  格式: $.data.list 或 $.data[0].name'),
              SizedBox(height: 8),
              Text('正则表达式:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('  格式: @Regex:xxx 或直接写正则'),
              SizedBox(height: 8),
              Text('URL模板:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('  {{key}} - 搜索关键词'),
              Text('  {{page}} - 页码'),
              Text('  {{(page-1)*20}} - 计算'),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了'))],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {String? hint, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.source == null ? '新建书源' : '编辑书源'),
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _saveSource, tooltip: '保存'),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: _showMoreMenu),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBaseTab(),
          _buildSearchTab(),
          _buildExploreTab(),
          _buildInfoTab(),
          _buildTocTab(),
          _buildContentTab(),
        ],
      ),
    );
  }

  Widget _buildBaseTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildTextField(_bookSourceUrl, '书源URL', hint: 'https://example.com'),
        _buildTextField(_bookSourceName, '书源名称', hint: '示例书源'),
        _buildTextField(_bookSourceGroup, '书源分组', hint: '默认'),
        _buildTextField(_bookSourceComment, '备注', hint: '书源说明'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: DropdownButtonFormField<int>(
            value: _bookSourceType,
            decoration: const InputDecoration(labelText: '书源类型', border: OutlineInputBorder(), isDense: true),
            items: const [
              DropdownMenuItem(value: 0, child: Text('小说')),
              DropdownMenuItem(value: 1, child: Text('音频')),
              DropdownMenuItem(value: 2, child: Text('图片')),
              DropdownMenuItem(value: 3, child: Text('文件')),
            ],
            onChanged: (v) => setState(() => _bookSourceType = v ?? 0),
          ),
        ),
        SwitchListTile(
          title: const Text('启用'),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        SwitchListTile(
          title: const Text('启用发现'),
          value: _enabledExplore,
          onChanged: (v) => setState(() => _enabledExplore = v),
        ),
        SwitchListTile(
          title: const Text('事件监听'),
          value: _eventListener,
          onChanged: (v) => setState(() => _eventListener = v),
        ),
        SwitchListTile(
          title: const Text('自定义按钮'),
          value: _customButton,
          onChanged: (v) => setState(() => _customButton = v),
        ),
        _buildTextField(_loginUrl, '登录URL', hint: '登录页面地址'),
        _buildTextField(_loginUi, '登录UI', hint: '登录界面配置JSON'),
        _buildTextField(_loginCheckJs, '登录检查JS', hint: 'JS脚本'),
        _buildTextField(_coverDecodeJs, '封面解码JS', hint: 'JS脚本'),
        _buildTextField(_bookUrlPattern, '书籍URL规则', hint: '正则匹配书籍URL'),
        _buildTextField(_header, 'HTTP请求头', hint: 'JSON格式'),
        _buildTextField(_variableComment, '变量注释', hint: '变量说明'),
        _buildTextField(_jsLib, 'jsLib', hint: 'JS库脚本'),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSearchTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildTextField(_searchUrl, '搜索URL', hint: 'https://example.com/search?q={{key}}&page={{page}}'),
        _buildTextField(_checkKeyWord, '校验关键字', hint: '用于校验搜索结果'),
        _buildTextField(_searchBookList, '书籍列表', hint: 'CSS/XPath/JSONPath'),
        _buildTextField(_searchName, '书名', hint: '名称选择规则'),
        _buildTextField(_searchAuthor, '作者', hint: '作者选择规则'),
        _buildTextField(_searchKind, '分类', hint: '分类选择规则'),
        _buildTextField(_searchWordCount, '字数', hint: '字数选择规则'),
        _buildTextField(_searchLastChapter, '最新章节', hint: '最新章节选择规则'),
        _buildTextField(_searchIntro, '简介', hint: '简介选择规则'),
        _buildTextField(_searchCoverUrl, '封面URL', hint: '封面选择规则'),
        _buildTextField(_searchBookUrl, '书籍URL', hint: '详情页URL选择规则'),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildExploreTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildTextField(_exploreUrl, '发现URL', hint: 'https://example.com/category'),
        _buildTextField(_exploreBookList, '书籍列表', hint: 'CSS/XPath/JSONPath'),
        _buildTextField(_exploreName, '书名', hint: '名称选择规则'),
        _buildTextField(_exploreAuthor, '作者', hint: '作者选择规则'),
        _buildTextField(_exploreKind, '分类', hint: '分类选择规则'),
        _buildTextField(_exploreWordCount, '字数', hint: '字数选择规则'),
        _buildTextField(_exploreLastChapter, '最新章节', hint: '最新章节选择规则'),
        _buildTextField(_exploreIntro, '简介', hint: '简介选择规则'),
        _buildTextField(_exploreCoverUrl, '封面URL', hint: '封面选择规则'),
        _buildTextField(_exploreBookUrl, '书籍URL', hint: '详情页URL选择规则'),
        _buildTextField(_homepageModules, '主页模块', hint: 'JSON格式模块配置'),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildInfoTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildTextField(_infoInit, '初始化', hint: 'JS初始化脚本'),
        _buildTextField(_infoName, '书名', hint: '名称选择规则'),
        _buildTextField(_infoAuthor, '作者', hint: '作者选择规则'),
        _buildTextField(_infoKind, '分类', hint: '分类选择规则'),
        _buildTextField(_infoWordCount, '字数', hint: '字数选择规则'),
        _buildTextField(_infoLastChapter, '最新章节', hint: '最新章节选择规则'),
        _buildTextField(_infoIntro, '简介', hint: '简介选择规则'),
        _buildTextField(_infoCoverUrl, '封面URL', hint: '封面选择规则'),
        _buildTextField(_infoTocUrl, '目录URL', hint: '目录页URL选择规则'),
        _buildTextField(_infoCanReName, '可重命名', hint: '是否允许重命名规则'),
        _buildTextField(_infoDownloadUrls, '下载URL规则', hint: '下载链接选择规则'),
        _buildTextField(_infoRelatedBooks, '相关书籍', hint: '相关书籍选择规则'),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildTocTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildTextField(_tocPreUpdateJs, '更新前JS', hint: 'JS脚本'),
        _buildTextField(_tocChapterList, '章节列表', hint: 'CSS/XPath/JSONPath'),
        _buildTextField(_tocChapterName, '章节名', hint: '章节名称选择规则'),
        _buildTextField(_tocChapterUrl, '章节URL', hint: '章节内容URL选择规则'),
        _buildTextField(_tocFormatJs, '格式化JS', hint: 'JS格式化脚本'),
        _buildTextField(_tocIsVolume, '是否卷', hint: '判断是否为卷的规则'),
        _buildTextField(_tocUpdateTime, '更新时间', hint: '更新时间选择规则'),
        _buildTextField(_tocIsVip, '是否VIP', hint: '判断是否VIP的规则'),
        _buildTextField(_tocIsPay, '是否付费', hint: '判断是否付费的规则'),
        _buildTextField(_tocNextTocUrl, '下一页目录URL', hint: '分页目录URL规则'),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildContentTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildTextField(_contentContent, '正文内容', hint: 'CSS/XPath/JSONPath', maxLines: 2),
        _buildTextField(_contentSubContent, '正文分块', hint: '分块选择规则'),
        _buildTextField(_contentTitle, '标题', hint: '章节标题选择规则'),
        _buildTextField(_contentNextContentUrl, '下一页正文URL', hint: '分页正文URL规则'),
        _buildTextField(_contentWebJs, 'WebJS', hint: 'JS脚本'),
        _buildTextField(_contentSourceRegex, '源正则', hint: '正则表达式'),
        _buildTextField(_contentReplaceRegex, '替换正则', hint: '正则替换规则'),
        _buildTextField(_contentImageStyle, '图片样式', hint: '图片显示样式'),
        _buildTextField(_contentImageDecode, '图片解码', hint: '图片解码JS'),
        _buildTextField(_contentPayAction, '付费操作', hint: '付费处理规则'),
        _buildTextField(_contentCallBackJs, '回调JS', hint: 'JS回调脚本'),
        const SizedBox(height: 24),
      ],
    );
  }
}
