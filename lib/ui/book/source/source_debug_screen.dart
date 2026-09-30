import 'package:flutter/material.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/source_engine.dart';

/// 书源调试：分步测试 搜索/发现/书籍信息/目录/正文，
/// 日志直接读取引擎的 debugLog（含真实请求 URL、响应字节、解码、规则匹配结果与异常），
/// 并可查看最近一次请求的原始响应文本，便于对照规则排查。
class SourceDebugScreen extends StatefulWidget {
  final BookSource source;

  const SourceDebugScreen({super.key, required this.source});

  @override
  State<SourceDebugScreen> createState() => _SourceDebugScreenState();
}

class _SourceDebugScreenState extends State<SourceDebugScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  final _bookUrlController = TextEditingController();
  final _tocUrlController = TextEditingController();
  final _contentUrlController = TextEditingController();
  final _exploreUrlController = TextEditingController(text: '');
  final _engine = BookSourceEngine();
  String _debugLog = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _exploreUrlController.text = widget.source.exploreUrl ?? '';
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _bookUrlController.dispose();
    _tocUrlController.dispose();
    _contentUrlController.dispose();
    _exploreUrlController.dispose();
    super.dispose();
  }

  /// 每次操作前清空引擎日志，操作后把引擎 debugLog 拉取到界面
  void _syncLog() {
    setState(() {
      _debugLog = _engine.debugLog.join('\n');
    });
  }

  void _begin() {
    _engine.clearDebugLog();
    setState(() {
      _isLoading = true;
      _debugLog = '';
    });
  }

  void _end() {
    _syncLog();
    setState(() => _isLoading = false);
  }

  /// 查看最近一次请求的原始响应
  void _showRawResponse() {
    final raw = _engine.lastRawResponse;
    if (raw == null || raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('还没有抓取过响应，请先执行一次操作')));
      return;
    }
    final preview = raw.length > 20000 ? '${raw.substring(0, 20000)}\n\n……（已截断，共 ${raw.length} 字符）' : raw;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('原始响应', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          height: 480,
          child: SingleChildScrollView(
            child: SelectableText(preview, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
      ),
    );
  }

  Future<void> _debugSearch() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) {
      setState(() => _debugLog = '错误: 请输入搜索关键词');
      return;
    }
    _begin();
    _log('开始搜索: $keyword');
    _log('书源: ${widget.source.bookSourceName} (${widget.source.bookSourceUrl})');
    try {
      final results = await _engine.search(widget.source, keyword);
      _log('搜索完成，找到 ${results.length} 个结果');
      for (var i = 0; i < results.length && i < 5; i++) {
        final b = results[i];
        final intro = b.intro ?? '';
        _log('  ${i + 1}. ${b.name} - ${b.author}');
        _log('     简介: ${intro.length > 50 ? '${intro.substring(0, 50)}...' : intro}');
        _log('     目录URL: ${b.noteUrl ?? b.bookUrl ?? 'N/A'}');
      }
      if (results.isNotEmpty) {
        _bookUrlController.text = results.first.noteUrl ?? results.first.bookUrl ?? '';
      }
    } catch (e) {
      _log('搜索失败: $e');
    }
    _end();
  }

  Future<void> _debugExplore(String url) async {
    if (url.trim().isEmpty) {
      setState(() => _debugLog = '错误: 请输入发现URL');
      return;
    }
    _begin();
    try {
      final books = await _engine.exploreByUrl(widget.source, url.trim());
      _log('发现完成，找到 ${books.length} 本书');
      for (final b in books.take(10)) {
        _log('  ${b.name} - ${b.author}');
      }
    } catch (e) {
      _log('发现失败: $e');
    }
    _end();
  }

  Future<void> _debugBookInfo() async {
    final url = _bookUrlController.text.trim();
    if (url.isEmpty) {
      setState(() => _debugLog = '错误: 请输入书籍URL');
      return;
    }
    _begin();
    try {
      final book = await _engine.getBookInfo(widget.source, url);
      if (book != null) {
        _log('书名: ${book.name}');
        _log('作者: ${book.author}');
        _log('简介: ${book.intro ?? 'N/A'}');
        _log('分类: ${book.kind ?? 'N/A'}');
        _log('最新章节: ${book.lastChapter ?? 'N/A'}');
        _log('封面: ${book.coverUrl ?? 'N/A'}');
        _log('目录URL: ${book.noteUrl ?? 'N/A'}');
        _tocUrlController.text = book.noteUrl ?? '';
      } else {
        _log('未获取到书籍信息');
      }
    } catch (e) {
      _log('获取书籍信息失败: $e');
    }
    _end();
  }

  Future<void> _debugToc() async {
    final url = _tocUrlController.text.trim();
    if (url.isEmpty) {
      setState(() => _debugLog = '错误: 请输入目录URL');
      return;
    }
    _begin();
    try {
      final chapters = await _engine.getToc(widget.source, url);
      _log('目录获取完成，共 ${chapters.length} 章');
      for (var i = 0; i < chapters.length && i < 10; i++) {
        _log('  ${i + 1}. ${chapters[i].title} -> ${chapters[i].url}');
      }
      if (chapters.isNotEmpty) {
        _contentUrlController.text = chapters.first.url;
      }
    } catch (e) {
      _log('获取目录失败: $e');
    }
    _end();
  }

  Future<void> _debugContent() async {
    final url = _contentUrlController.text.trim();
    if (url.isEmpty) {
      setState(() => _debugLog = '错误: 请输入正文URL');
      return;
    }
    _begin();
    try {
      final content = await _engine.getContent(widget.source, url);
      if (content != null) {
        _log('正文获取完成，长度: ${content.length} 字符');
        _log('前200字: ${content.length > 200 ? content.substring(0, 200) : content}');
      } else {
        _log('未获取到正文内容');
      }
    } catch (e) {
      _log('获取正文失败: $e');
    }
    _end();
  }

  void _log(String message) => _engine.debugLog.add(message);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('调试: ${widget.source.bookSourceName}'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '搜索'),
            Tab(text: '发现'),
            Tab(text: '书籍信息'),
            Tab(text: '目录'),
            Tab(text: '正文'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSearchTab(),
                _buildExploreTab(),
                _buildBookInfoTab(),
                _buildTocTab(),
                _buildContentTab(),
              ],
            ),
          ),
          Container(
            height: 230,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('调试日志', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton(
                          onPressed: _isLoading ? null : _showRawResponse,
                          child: const Text('原始响应', style: TextStyle(fontSize: 12)),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _debugLog = ''),
                          child: const Text('清空', style: TextStyle(fontSize: 12)),
                        ),
                      ]),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: SelectableText(
                      _debugLog.isEmpty ? '暂无日志\n\n点击上方按钮执行一次操作，将显示请求 URL、响应、规则匹配结果与异常。' : _debugLog,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExploreTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        TextField(
          controller: _exploreUrlController,
          decoration: const InputDecoration(labelText: '发现URL', border: OutlineInputBorder()),
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isLoading ? null : () => _debugExplore(_exploreUrlController.text),
            icon: _isLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow),
            label: const Text('执行发现'),
          ),
        ),
        const SizedBox(height: 12),
        Text('规则列表: ${widget.source.ruleExplore?['bookList'] ?? 'N/A'}', style: const TextStyle(fontSize: 12)),
      ]),
    );
  }

  Widget _buildSearchTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: '搜索关键词',
              hintText: '输入书名或作者',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isLoading ? null : _debugSearch,
            icon: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search),
            label: const Text('测试搜索'),
          ),
          const SizedBox(height: 16),
          Text('搜索URL: ${widget.source.searchUrl ?? '未配置'}', style: const TextStyle(fontSize: 12)),
          if (widget.source.ruleSearch != null) ...[
            const SizedBox(height: 8),
            Text('规则列表: ${widget.source.ruleSearch!['bookList'] ?? 'N/A'}', style: const TextStyle(fontSize: 12)),
            Text('规则书名: ${widget.source.ruleSearch!['name'] ?? 'N/A'}', style: const TextStyle(fontSize: 12)),
            Text('规则作者: ${widget.source.ruleSearch!['author'] ?? 'N/A'}', style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _buildBookInfoTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _bookUrlController,
            decoration: const InputDecoration(
              labelText: '书籍URL',
              hintText: '输入书籍详情页URL',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isLoading ? null : _debugBookInfo,
            icon: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.info_outline),
            label: const Text('测试书籍信息'),
          ),
        ],
      ),
    );
  }

  Widget _buildTocTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _tocUrlController,
            decoration: const InputDecoration(
              labelText: '目录URL',
              hintText: '输入目录页URL',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isLoading ? null : _debugToc,
            icon: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.list_alt),
            label: const Text('测试目录'),
          ),
        ],
      ),
    );
  }

  Widget _buildContentTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _contentUrlController,
            decoration: const InputDecoration(
              labelText: '正文URL',
              hintText: '输入章节内容页URL',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isLoading ? null : _debugContent,
            icon: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.article),
            label: const Text('测试正文'),
          ),
        ],
      ),
    );
  }
}
